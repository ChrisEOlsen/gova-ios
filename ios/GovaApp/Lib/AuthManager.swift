import Foundation
import Security

struct UserInfo: Codable {
    let id: Int
    let name: String
    let email: String
}

final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var isLoggedIn: Bool = false
    @Published private(set) var currentUser: UserInfo?

    private let keychainKey = "gova.auth.token"

    private init() {
        isLoggedIn = readTokenFromKeychain() != nil
    }

    // nonisolated so APIClient can read the token from any thread/actor context
    nonisolated var token: String? {
        readTokenFromKeychain()
    }

    @MainActor
    func login(token: String, user: UserInfo) {
        saveTokenToKeychain(token)
        currentUser = user
        isLoggedIn = true
    }

    @MainActor
    func logout() {
        deleteTokenFromKeychain()
        currentUser = nil
        isLoggedIn = false
    }

    // MARK: - Keychain (thread-safe Security framework calls)

    private func readTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveTokenToKeychain(_ token: String) {
        deleteTokenFromKeychain()
        let query: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrAccount as String:    keychainKey,
            kSecValueData as String:      Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func deleteTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey
        ]
        SecItemDelete(query as CFDictionary)
    }
}
