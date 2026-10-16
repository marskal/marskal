import CryptoKit
import Foundation

/// The app's OAuth client in Hydra (ADR 0029, `priv/hydra/clients/ios.json`).
public enum OAuthClient {
    public static let id = "marskal-ios"
    public static let callbackScheme = "app.marskal.ios"
    public static let redirectURI = "app.marskal.ios:/oauth/callback"
    public static let scope = "offline_access sync:read sync:write"
}

/// A server's address, as the user typed it, made into a base URL.
public enum ServerAddress {
    /// `marskal.example` becomes `https://marskal.example`. A scheme other
    /// than http or https, or no host, is refused.
    public static func parse(_ text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }

        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty
        else { return nil }

        components.scheme = scheme
        components.host = host.lowercased()
        while components.path.hasSuffix("/") { components.path.removeLast() }
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

/// Hydra's endpoints, from the server's metadata (RFC 8414, ADR 0021).
public struct Endpoints: Codable, Equatable, Sendable {
    public var authorizationEndpoint: URL
    public var tokenEndpoint: URL
    public var revocationEndpoint: URL
}

/// A token response, kept until the access token expires.
public struct Tokens: Codable, Equatable, Sendable {
    public var access: String
    public var refresh: String
    public var expiresAt: Date

    /// True a minute early, so a request does not go out with a token
    /// that lapses on the way.
    func expired(at now: Date) -> Bool {
        expiresAt.timeIntervalSince(now) < 60
    }
}

struct TokenResponse: Decodable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Double

    func tokens(keeping refresh: String? = nil, at now: Date) throws(ServerError) -> Tokens {
        guard let refresh = refreshToken ?? refresh else { throw .oauth("no_refresh_token") }
        return Tokens(access: accessToken, refresh: refresh, expiresAt: now.addingTimeInterval(expiresIn))
    }
}

/// One sign-in through the system's web sheet: the authorization code
/// grant with PKCE (RFC 7636). Start it, show `url`, and finish it with
/// the URL the sheet hands back.
public struct SignIn: Sendable {
    public let server: URL
    public let endpoints: Endpoints
    public let url: URL
    let verifier: String
    let state: String

    /// Reads the server's metadata and prepares the authorization URL.
    public static func start(server: URL, session: URLSession = .shared) async throws(ServerError) -> SignIn {
        let http = HTTP(session: session)
        let metadata = server.appending(path: ".well-known/oauth-authorization-server")
        let endpoints = try await http.json(Endpoints.self, for: URLRequest(url: metadata))

        let verifier = randomToken()
        let state = randomToken()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL

        var components = URLComponents(url: endpoints.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: OAuthClient.id),
            URLQueryItem(name: "redirect_uri", value: OAuthClient.redirectURI),
            URLQueryItem(name: "scope", value: OAuthClient.scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = components?.url else { throw .badAddress }

        return SignIn(server: server, endpoints: endpoints, url: url, verifier: verifier, state: state)
    }

    /// Trades the code in `callback` for tokens.
    public func finish(
        callback: URL, session: URLSession = .shared, now: Date = .now
    ) async throws(ServerError) -> Tokens {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }

        if let error = value("error") { throw .oauth(error) }
        guard value("state") == state, let code = value("code") else { throw .oauth("invalid_state") }

        let request = URLRequest.form(endpoints.tokenEndpoint, [
            "grant_type": "authorization_code",
            "client_id": OAuthClient.id,
            "redirect_uri": OAuthClient.redirectURI,
            "code": code,
            "code_verifier": verifier,
        ])
        return try await HTTP(session: session).json(TokenResponse.self, for: request).tokens(at: now)
    }
}

/// 32 random bytes, base64url: a PKCE verifier or a state value.
func randomToken() -> String {
    var generator = SystemRandomNumberGenerator()
    return Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }).base64URL
}

extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
