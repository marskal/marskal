import Foundation
import MarskalCore

/// A signed-in server: its tokens, and the sync with it (ADR 0019, 0029).
///
/// One actor per server. It refreshes one at a time, so the rotating
/// refresh token is never sent twice, and runs one sync at a time.
public actor Session {
    public nonisolated let server: URL
    private let http: HTTP
    private let tokens: TokenStore
    private let clock: @Sendable () -> Date
    private var endpoints: Endpoints?
    private var refreshing: Task<Tokens, any Error>?
    private var syncing: Task<SyncReport, any Error>?

    static let pushBatch: UInt64 = 1000

    public init(
        server: URL,
        tokens: TokenStore,
        session: URLSession = .shared,
        clock: @escaping @Sendable () -> Date = { .now }
    ) {
        self.server = server
        self.tokens = tokens
        self.http = HTTP(session: session)
        self.clock = clock
    }

    /// Whether tokens are kept for this server.
    public nonisolated var isSignedIn: Bool {
        tokens.load(server: server) != nil
    }

    /// Keeps the tokens a sign-in brought.
    public func signedIn(_ new: Tokens, endpoints: Endpoints) {
        self.endpoints = endpoints
        tokens.save(new, server: server)
    }

    /// Revokes the refresh token at Hydra, which signs this device out on
    /// the server, and forgets the tokens. A revocation that fails still
    /// forgets them; the device can be signed out from the web app.
    public func signOut() async {
        guard let current = tokens.load(server: server) else { return }
        tokens.delete(server: server)
        if let endpoints = try? await self.endpoints() {
            let request = URLRequest.form(endpoints.revocationEndpoint, [
                "client_id": OAuthClient.id,
                "token": current.refresh,
            ])
            _ = try? await http.data(for: request)
        }
    }

    /// Pushes the outbox, then pulls until the server has nothing more.
    /// A sync already under way is joined, not started again.
    public func sync(_ store: Store) async throws -> SyncReport {
        if let syncing { return try await syncing.value }
        let task = Task { try await self.run(store) }
        syncing = task
        defer { syncing = nil }
        return try await task.value
    }

    private func run(_ store: Store) async throws -> SyncReport {
        var report = SyncReport()

        while let batch = try store.pushBatch(limit: Self.pushBatch) {
            var request = URLRequest(url: server.appending(path: "api/v1/sync/push"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = Data(batch.body.utf8)

            let response = try await authorized(request)
            let summary = try store.recordPush(response: String(decoding: response, as: UTF8.self))
            report.pushed += summary.accepted
            report.rejected += summary.rejected

            // The server stopped part way; the rest go next time.
            if summary.answered < batch.count { break }
        }

        while true {
            var components = URLComponents(
                url: server.appending(path: "api/v1/sync/pull"), resolvingAgainstBaseURL: false)
            if let cursor = try store.pullCursor() {
                components?.queryItems = [URLQueryItem(name: "cursor", value: String(cursor))]
            }
            guard let url = components?.url else { throw ServerError.badAddress }

            let response: Data
            do {
                response = try await authorized(URLRequest(url: url))
            } catch ServerError.gone {
                try store.resetCursor()
                continue
            }

            let pull = try store.applyPull(response: String(decoding: response, as: UTF8.self))
            report.pulls += 1
            if !pull.more { break }
        }

        try store.markSynced()
        return report
    }

    // Sends with the access token, refreshing first if it has expired, and
    // once more after a 401.
    private func authorized(_ request: URLRequest) async throws -> Data {
        var token = try await accessToken()
        for attempt in 0..<2 {
            var request = request
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            do {
                return try await http.data(for: request)
            } catch .notSignedIn where attempt == 0 {
                token = try await refreshed(after: token)
            }
        }
        throw ServerError.notSignedIn
    }

    private func accessToken() async throws -> String {
        guard let current = tokens.load(server: server) else { throw ServerError.notSignedIn }
        if !current.expired(at: clock()) { return current.access }
        return try await refreshed(after: current.access)
    }

    // A refresh, unless another call already replaced `rejected`.
    private func refreshed(after rejected: String) async throws -> String {
        if let refreshing { return try await refreshing.value.access }
        guard let current = tokens.load(server: server) else { throw ServerError.notSignedIn }
        if current.access != rejected { return current.access }

        let task = Task { try await self.refresh(current) }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value.access
    }

    private func refresh(_ current: Tokens) async throws -> Tokens {
        let request = URLRequest.form(try await endpoints().tokenEndpoint, [
            "grant_type": "refresh_token",
            "client_id": OAuthClient.id,
            "refresh_token": current.refresh,
        ])

        do {
            let new = try await http.json(TokenResponse.self, for: request)
                .tokens(keeping: current.refresh, at: clock())
            tokens.save(new, server: server)
            return new
        } catch .oauth("invalid_grant") {
            // Revoked, expired, or reused: this grant is over.
            tokens.delete(server: server)
            throw ServerError.notSignedIn
        }
    }

    private func endpoints() async throws(ServerError) -> Endpoints {
        if let endpoints { return endpoints }
        let metadata = server.appending(path: ".well-known/oauth-authorization-server")
        let found = try await http.json(Endpoints.self, for: URLRequest(url: metadata))
        endpoints = found
        return found
    }
}

/// What one sync did.
public struct SyncReport: Equatable, Sendable {
    public var pushed: UInt64 = 0
    public var rejected: UInt64 = 0
    public var pulls = 0
}
