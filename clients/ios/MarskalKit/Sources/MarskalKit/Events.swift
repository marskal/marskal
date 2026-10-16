import Foundation
import os

private let log = Logger(subsystem: "app.marskal.ios", category: "events")

/// Reads the sync event stream (ADR 0030) one line at a time. The server
/// sends an `id:` and a `data: {"cursor":…}` line per event, a `retry:`
/// line once, and comments to keep the connection alive.
struct EventParser {
    /// The reconnect delay the server asked for.
    private(set) var retry: Duration?
    private(set) var lastEventID: Int64?
    private var id: Int64?

    /// The cursor of the event a line completes, if it completes one.
    mutating func read(_ line: some StringProtocol) -> Int64? {
        if line.isEmpty || line.hasPrefix(":") { return nil }

        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = Substring(line[..<colon])
            value = Substring(line[line.index(after: colon)...])
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }

        switch field {
        case "retry":
            if let ms = Int(value) { retry = .milliseconds(ms) }
        case "id":
            id = Int64(value)
            if let id { lastEventID = id }
        case "data":
            let changed = try? JSONDecoder().decode(Changed.self, from: Data(value.utf8))
            return changed?.cursor ?? id
        default:
            break
        }
        return nil
    }
}

private struct Changed: Decodable {
    var cursor: Int64
}

extension Session {
    /// Listens to the sync event stream until cancelled, calling `changed`
    /// with each cursor the server sends (ADR 0030). It reconnects after the
    /// delay the server asks for, with `Last-Event-ID`, and refreshes the
    /// access token when the server refuses it. A signed-out device ends it.
    public func listen(changed: @escaping @Sendable (Int64) async -> Void) async {
        var parser = EventParser()
        var failures = 0

        while !Task.isCancelled {
            do {
                try await connect(parser: &parser, changed: changed)
                failures = 0
            } catch is CancellationError {
                return
            } catch ServerError.notSignedIn {
                log.debug("Event stream: signed out")
                return
            } catch {
                failures += 1
                log.debug("Event stream failed: \(String(describing: error), privacy: .public)")
            }

            // The server's delay, longer after failures in a row, at most a
            // minute.
            let base = parser.retry ?? .seconds(5)
            let delay = min(base * (1 << min(failures, 4)), .seconds(60))
            try? await Task.sleep(for: failures == 0 ? base : delay)
        }
    }

    private func connect(
        parser: inout EventParser, changed: @Sendable (Int64) async -> Void
    ) async throws {
        var token = try await accessToken()

        for attempt in 0..<2 {
            var request = URLRequest(url: server.appending(path: "api/v1/sync/events"))
            request.setValue("text/event-stream", forHTTPHeaderField: "accept")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            if let last = parser.lastEventID {
                request.setValue(String(last), forHTTPHeaderField: "last-event-id")
            }

            let (bytes, response) = try await urlSession.bytes(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            switch status {
            case 200:
                log.debug("Event stream open")
                for try await line in bytes.lines {
                    if let cursor = parser.read(line) {
                        log.debug("Event stream: changed, cursor \(cursor)")
                        await changed(cursor)
                    }
                }
                log.debug("Event stream closed by the server")
                return
            case 401 where attempt == 0:
                token = try await refreshed(after: token)
            case 401:
                throw ServerError.notSignedIn
            case 403:
                throw ServerError.forbidden
            default:
                throw ServerError.status(status)
            }
        }
    }
}
