import Foundation
import Security

struct UserInfo: Codable {
    let id: Int
    let name: String
    let email: String
}

/// Owns the bearer token. The Keychain is the durable store; the in-memory copy
/// is what `APIClient` reads on every request, so a request does not pay for a
/// Keychain lookup.
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var isLoggedIn: Bool = false
    @Published private(set) var currentUser: UserInfo?

    private let keychainKey = "gova.auth.token"
    private let lock = NSLock()
    private var cachedToken: String?

    private init() {
        cachedToken = readTokenFromKeychain()
        isLoggedIn = cachedToken != nil
    }

    /// nonisolated so APIClient can read it from any thread or actor context.
    nonisolated var token: String? {
        lock.lock()
        defer { lock.unlock() }
        return cachedToken
    }

    @MainActor
    func login(token: String, user: UserInfo) {
        setToken(token)
        currentUser = user
        isLoggedIn = true
    }

    @MainActor
    func logout() {
        setToken(nil)
        currentUser = nil
        isLoggedIn = false
    }

    private func setToken(_ token: String?) {
        lock.lock()
        cachedToken = token
        lock.unlock()

        deleteTokenFromKeychain()
        if let token {
            saveTokenToKeychain(token)
        }
    }

    // MARK: - Keychain

    private func readTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveTokenToKeychain(_ token: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func deleteTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
