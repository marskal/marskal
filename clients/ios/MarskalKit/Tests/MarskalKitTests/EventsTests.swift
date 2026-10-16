import Foundation
import Testing
@testable import MarskalKit

struct EventParserTests {
    @Test func anEventIsItsCursor() {
        var parser = EventParser()
        let lines = ["retry: 5000", "", "id: 42", "event: changed", #"data: {"cursor":42}"#, ""]
        let cursors = lines.compactMap { parser.read($0) }

        #expect(cursors == [42])
        #expect(parser.lastEventID == 42)
        #expect(parser.retry == .milliseconds(5000))
    }

    @Test func commentsAndUnknownFieldsAreIgnored() {
        var parser = EventParser()
        #expect(parser.read(": keep-alive") == nil)
        #expect(parser.read("event: changed") == nil)
        #expect(parser.read("something else") == nil)
        #expect(parser.lastEventID == nil)
    }
}

/// Collects what the stream calls back with, for a test to wait on.
private actor Received {
    var cursors: [Int64] = []
    func add(_ cursor: Int64) { cursors.append(cursor) }
}

struct ListenTests {
    let tokens = MemoryTokenStore()

    init() {
        tokens.save(Tokens(access: "a1", refresh: "r1", expiresAt: .now.addingTimeInterval(3600)), server: server)
    }

    @Test func reconnectsWithTheLastEventID() async throws {
        let stub = StubServer { request, _ in
            let last = request.value(forHTTPHeaderField: "last-event-id")
            let cursor = last == nil ? 7 : 9
            return (200, "retry: 10\n\nid: \(cursor)\nevent: changed\ndata: {\"cursor\":\(cursor)}\n\n")
        }
        let received = Received()
        let session = Session(server: server, tokens: tokens, session: stub.session)

        let task = Task { await session.listen { await received.add($0) } }
        try await waitUntil { await received.cursors.count >= 2 }
        task.cancel()

        #expect(await Array(received.cursors.prefix(2)) == [7, 9])
        #expect(stub.requests[0].request.value(forHTTPHeaderField: "last-event-id") == nil)
        #expect(stub.requests[1].request.value(forHTTPHeaderField: "last-event-id") == "7")
        #expect(stub.requests[0].request.value(forHTTPHeaderField: "authorization") == "Bearer a1")
        #expect(stub.paths().allSatisfy { $0 == "/api/v1/sync/events" })
    }

    @Test func aRefusedTokenIsRefreshed() async throws {
        let stub = StubServer { request, _ in
            switch request.url?.path() {
            case "/.well-known/oauth-authorization-server": (200, metadata)
            case "/oauth2/token": (200, #"{"access_token": "a2", "refresh_token": "r2", "expires_in": 3600}"#)
            default:
                request.value(forHTTPHeaderField: "authorization") == "Bearer a1"
                    ? (401, #"{"error": "invalid_token"}"#)
                    : (200, "retry: 10\n\nid: 3\ndata: {\"cursor\":3}\n\n")
            }
        }
        let received = Received()
        let session = Session(server: server, tokens: tokens, session: stub.session)

        let task = Task { await session.listen { await received.add($0) } }
        try await waitUntil { await received.cursors.contains(3) }
        task.cancel()

        #expect(tokens.load(server: server)?.access == "a2")
    }

    @Test func aSignedOutDeviceStopsListening() async throws {
        let stub = StubServer { request, _ in
            request.url?.path() == "/oauth2/token"
                ? (400, #"{"error": "invalid_grant"}"#)
                : request.url?.path() == "/.well-known/oauth-authorization-server"
                    ? (200, metadata) : (401, #"{"error": "invalid_token"}"#)
        }
        let session = Session(server: server, tokens: tokens, session: stub.session)

        // Returns by itself, without being cancelled.
        await session.listen { _ in }
        #expect(tokens.load(server: server) == nil)
    }
}

private func waitUntil(_ check: () async -> Bool) async throws {
    for _ in 0..<200 {
        if await check() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("timed out")
}
