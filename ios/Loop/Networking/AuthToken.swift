import Foundation
import Security

/// The bearer token, kept in the Keychain. Tokens never expire; signing out just forgets it.
enum AuthToken {
    private static let service = "com.stacked.loop"
    private static let account = APIConfig.useMocks ? "token.mock" : "token.live"
    private static let lock = NSLock()
    private static var cached: String??

    static var current: String? {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        let value = read()
        cached = .some(value)
        return value
    }

    static func set(_ token: String?) {
        lock.lock(); defer { lock.unlock() }
        cached = .some(token)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard let token, let data = token.data(using: .utf8) else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
