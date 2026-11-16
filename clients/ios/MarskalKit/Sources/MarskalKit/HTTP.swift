import Foundation

/// What went wrong talking to the server, as the app tells it apart.
public enum ServerError: Error, Equatable, Sendable {
    /// No usable tokens: never signed in, signed out, or the grant revoked.
    case notSignedIn
    /// The token lacks a scope this call needs.
    case forbidden
    /// The cursor is older than the server keeps; pull a snapshot.
    case gone
    /// The server needs this release of the app or a later one (ADR 0040).
    case clientOutdated(minimum: String)
    /// An OAuth error code from Hydra, such as `invalid_grant`.
    case oauth(String)
    /// Any other answer the call did not expect.
    case status(Int)
    /// No answer, or one that could not be read.
    case network(String)
    /// The address does not look like a server.
    case badAddress
}

/// URLSession with the status mapping every call shares (ADR 0019).
struct HTTP: Sendable {
    let session: URLSession

    func data(for request: URLRequest) async throws(ServerError) -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .network(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            return data
        case 401 where !String(decoding: data, as: UTF8.self).contains("invalid_client"):
            throw .notSignedIn
        case 403:
            throw .forbidden
        case 410:
            throw .gone
        case 426:
            throw .clientOutdated(minimum: Self.minimum(in: data))
        default:
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let code = body?["error"] as? String {
                throw .oauth(code)
            }
            throw .status(status)
        }
    }

    /// The version a `426` names.
    static func minimum(in data: Data) -> String {
        let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return body?["minimum_version"] as? String ?? "?"
    }

    func json<T: Decodable>(_: T.Type, for request: URLRequest) async throws(ServerError) -> T {
        let data = try await data(for: request)
        do {
            return try JSONDecoder.snakeCase.decode(T.self, from: data)
        } catch {
            throw .network("unreadable answer from the server")
        }
    }
}

extension URLRequest {
    /// Names the app and its release to the sync API (ADR 0040).
    mutating func nameClient() {
        setValue("\(OAuthClient.id)/\(OAuthClient.version)", forHTTPHeaderField: "marskal-client")
    }

    /// A form post, as the OAuth endpoints take.
    static func form(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        var components = URLComponents()
        components.queryItems = fields.sorted { $0.key < $1.key }.map(URLQueryItem.init)
        // URLComponents leaves `+` alone; in a form body it means a space.
        request.httpBody = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)
        return request
    }
}

extension JSONDecoder {
    static let snakeCase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
