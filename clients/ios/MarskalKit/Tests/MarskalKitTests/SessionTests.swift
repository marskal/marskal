import Foundation
import Testing
@testable import MarskalKit

struct SessionTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let tokens = MemoryTokenStore()

    func session(_ stub: StubServer) -> Session {
        let now = now
        return Session(server: server, tokens: tokens, session: stub.session, clock: { now })
    }

    func signIn(access: String = "a1", expiresIn: TimeInterval = 3600) {
        tokens.save(Tokens(access: access, refresh: "r1", expiresAt: now.addingTimeInterval(expiresIn)), server: server)
    }

    @Test func aSyncPushesTheOutboxThenPulls() async throws {
        signIn()
        let store = try temporaryStore()
        _ = try store.addTask(new: NewTask(title: "Buy milk"))
        let commandId = try #require(
            (try JSONSerialization.jsonObject(with: Data(try store.pushBatch(limit: 10)!.body.utf8))
                as? [String: [[String: Any]]])?["commands"]?.first?["id"] as? String)

        let stub = StubServer { request, _ in
            switch request.url?.path() {
            case "/api/v1/sync/push": (200, #"{"results": [{"id": "\#(commandId)", "status": "applied"}]}"#)
            default: (200, pullBody(cursor: 9))
            }
        }

        let report = try await session(stub).sync(store)

        #expect(report == SyncReport(pushed: 1, rejected: 0, pulls: 1))
        #expect(stub.paths() == ["/api/v1/sync/push", "/api/v1/sync/pull"])
        #expect(stub.requests.allSatisfy { $0.request.value(forHTTPHeaderField: "authorization") == "Bearer a1" })
        #expect(stub.requests[1].request.url?.query() == nil)
        #expect(try store.pullCursor() == 9)
        #expect(try store.status().pending == 0)
        #expect(try store.status().lastSyncedAt != nil)
    }

    @Test func aPullFollowsMoreAndTheCursor() async throws {
        signIn()
        let store = try temporaryStore()
        let stub = StubServer { request, _ in
            request.url?.query() == nil ? (200, pullBody(cursor: 5, more: true)) : (200, pullBody(cursor: 8))
        }

        let report = try await session(stub).sync(store)

        #expect(report.pulls == 2)
        #expect(stub.requests.map { $0.request.url?.query() } == [nil, "cursor=5"])
        #expect(try store.pullCursor() == 8)
    }

    @Test func goneAsksForASnapshot() async throws {
        signIn()
        let store = try temporaryStore()
        _ = try store.applyPull(response: pullBody(cursor: 3))
        let stub = StubServer { request, _ in
            request.url?.query() == "cursor=3" ? (410, #"{"error": "gone"}"#) : (200, pullBody(cursor: 12))
        }

        _ = try await session(stub).sync(store)

        #expect(stub.requests.map { $0.request.url?.query() } == ["cursor=3", nil])
        #expect(try store.pullCursor() == 12)
    }

    @Test func anExpiredTokenIsRefreshedFirst() async throws {
        signIn(expiresIn: 30)
        let store = try temporaryStore()
        let stub = StubServer { request, _ in
            switch request.url?.path() {
            case "/.well-known/oauth-authorization-server": (200, metadata)
            case "/oauth2/token": (200, #"{"access_token": "a2", "refresh_token": "r2", "expires_in": 3600}"#)
            default: (200, pullBody(cursor: 1))
            }
        }

        _ = try await session(stub).sync(store)

        #expect(stub.paths() == ["/.well-known/oauth-authorization-server", "/oauth2/token", "/api/v1/sync/pull"])
        #expect(form(stub.requests[1].body)["refresh_token"] == "r1")
        #expect(stub.requests[2].request.value(forHTTPHeaderField: "authorization") == "Bearer a2")
        #expect(tokens.load(server: server)?.refresh == "r2")
    }

    @Test func a401RefreshesOnceAndRetries() async throws {
        signIn()
        let store = try temporaryStore()
        let stub = StubServer { request, _ in
            switch request.url?.path() {
            case "/.well-known/oauth-authorization-server": (200, metadata)
            case "/oauth2/token": (200, #"{"access_token": "a2", "refresh_token": "r2", "expires_in": 3600}"#)
            default:
                request.value(forHTTPHeaderField: "authorization") == "Bearer a1"
                    ? (401, #"{"error": "unauthorized"}"#) : (200, pullBody(cursor: 1))
            }
        }

        _ = try await session(stub).sync(store)

        #expect(stub.paths().filter { $0 == "/oauth2/token" }.count == 1)
        #expect(stub.paths().last == "/api/v1/sync/pull")
    }

    @Test func aRevokedGrantSignsOut() async throws {
        signIn(expiresIn: 0)
        let store = try temporaryStore()
        let stub = StubServer { request, _ in
            request.url?.path() == "/oauth2/token" ? (400, #"{"error": "invalid_grant"}"#) : (200, metadata)
        }

        await #expect(throws: ServerError.notSignedIn) { try await session(stub).sync(store) }
        #expect(tokens.load(server: server) == nil)
    }

    @Test func syncsAtOnceShareOneRun() async throws {
        signIn()
        let store = try temporaryStore()
        let stub = StubServer { _, _ in (200, pullBody(cursor: 1)) }
        let session = session(stub)

        async let first = session.sync(store)
        async let second = session.sync(store)
        _ = try await (first, second)

        #expect(stub.paths().count <= 2)
    }

    @Test func signingOutRevokesTheRefreshToken() async throws {
        signIn()
        let stub = StubServer { request, _ in
            request.url?.path() == "/oauth2/revoke" ? (200, "") : (200, metadata)
        }

        await session(stub).signOut()

        #expect(tokens.load(server: server) == nil)
        #expect(stub.paths().last == "/oauth2/revoke")
        #expect(form(stub.requests.last!.body)["token"] == "r1")
    }
}
