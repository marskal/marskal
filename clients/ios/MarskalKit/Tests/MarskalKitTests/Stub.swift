import Foundation
@testable import MarskalKit

/// A fake server: each test gets its own URLSession and answers requests
/// with a handler, and can read back what was sent.
final class StubServer: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest, Data) -> (Int, String)

    let id = UUID().uuidString
    let session: URLSession
    private let lock = NSLock()
    private var handler: Handler
    private var sent: [(URLRequest, Data)] = []

    nonisolated(unsafe) static var servers: [String: StubServer] = [:]
    static let registry = NSLock()

    init(_ handler: @escaping Handler) {
        self.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        configuration.httpAdditionalHeaders = ["x-stub": id]
        session = URLSession(configuration: configuration)
        Self.registry.withLock { Self.servers[id] = self }
    }

    var requests: [(request: URLRequest, body: Data)] {
        lock.withLock { sent.map { ($0.0, $0.1) } }
    }

    func paths() -> [String] {
        requests.map { $0.request.url?.path() ?? "" }
    }

    fileprivate func answer(_ request: URLRequest, _ body: Data) -> (Int, String) {
        lock.withLock { sent.append((request, body)) }
        return handler(request, body)
    }
}

final class StubProtocol: URLProtocol {
    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "x-stub") ?? ""
        guard let server = StubServer.registry.withLock({ StubServer.servers[id] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }

        let (status, body) = server.answer(request, Self.body(of: request))
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["content-type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    // URLSession hands a protocol the body as a stream.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

let server = URL(string: "https://marskal.example")!

let metadata = """
    {"authorization_endpoint": "https://marskal.example/oauth2/auth",
     "token_endpoint": "https://marskal.example/oauth2/token",
     "revocation_endpoint": "https://marskal.example/oauth2/revoke"}
    """

func form(_ body: Data) -> [String: String] {
    var components = URLComponents()
    components.percentEncodedQuery = String(decoding: body, as: UTF8.self)
    return Dictionary(
        (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
}

func pullBody(cursor: Int, more: Bool = false, user: String = "u1") -> String {
    """
    {"cursor": \(cursor), "snapshot": true, "more": \(more),
     "user": {"id": "\(user)", "timezone": "Europe/Copenhagen"}, "rows": {}, "gone": []}
    """
}

func temporaryStore() throws -> Store {
    let path = FileManager.default.temporaryDirectory
        .appending(path: "marskal-\(UUID().uuidString).sqlite").path()
    return try Store.open(path: path)
}
