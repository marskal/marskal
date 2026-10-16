import Foundation
import Security

/// Where one server's tokens are kept.
public protocol TokenStore: Sendable {
    func load(server: URL) -> Tokens?
    func save(_ tokens: Tokens, server: URL)
    func delete(server: URL)
}

/// The Keychain, readable only by the app and only after the first unlock
/// (ADR 0029). The widget never reaches the server, so it needs no access.
public struct KeychainTokenStore: TokenStore {
    static let service = "app.marskal.ios.tokens"

    public init() {}

    public func load(server: URL) -> Tokens? {
        var query = Self.query(server)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: data)
    }

    public func save(_ tokens: Tokens, server: URL) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(Self.query(server) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = Self.query(server).merging(attributes) { _, new in new }
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    public func delete(server: URL) {
        SecItemDelete(Self.query(server) as CFDictionary)
    }

    private static func query(_ server: URL) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: server.absoluteString,
        ]
    }
}

/// Tokens in memory, for tests and previews.
public final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [URL: Tokens] = [:]

    public init() {}

    public func load(server: URL) -> Tokens? {
        lock.withLock { tokens[server] }
    }

    public func save(_ tokens: Tokens, server: URL) {
        lock.withLock { self.tokens[server] = tokens }
    }

    public func delete(server: URL) {
        _ = lock.withLock { tokens.removeValue(forKey: server) }
    }
}
