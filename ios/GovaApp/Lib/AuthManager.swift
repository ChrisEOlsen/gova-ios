import Foundation
import os
import Security

struct UserInfo: Codable {
    let id: Int
    let name: String
    let email: String
}

/// The `POST /api/v1/auth/login_token` response. Fixed by
/// docs/API-CONTRACT.md § Authentication — `{ "token", "user" }` — so it lives
/// here rather than being re-declared per app.
struct LoginResponse: Codable {
    let token: String
    let user: UserInfo
}

/// The credentials `login_token` and `register` take.
struct LoginRequest: Encodable {
    let email: String
    let password: String
}

/// Owns the bearer token. The Keychain is the durable store; the in-memory copy
/// is what `APIClient` reads on every request, so a request does not pay for a
/// Keychain lookup.
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var isLoggedIn: Bool = false
    @Published private(set) var currentUser: UserInfo?

    /// True from launch until `restoreSession()` has settled, when a token was
    /// found in the Keychain. Without it the app renders signed-in screens on the
    /// strength of a token that may be dead, and a user with an expired one sees
    /// a flash of the app, a burst of failing requests, then the login screen.
    /// The root view shows a splash while this is true.
    @Published private(set) var isRestoring: Bool = false

    private let keychainService = "com.gova.auth"
    private let keychainKey = "gova.auth.token"
    private let lock = NSLock()
    private var cachedToken: String?

    private let log = Logger(subsystem: "com.gova.auth", category: "keychain")

    private init() {
        cachedToken = readTokenFromKeychain()
        isLoggedIn = cachedToken != nil
        // Set here rather than inside restoreSession so there is no window in
        // which a stale session looks live. GovaAppApp always calls
        // restoreSession at launch, which is what clears it.
        isRestoring = cachedToken != nil
    }

    /// nonisolated so APIClient can read it from any thread or actor context.
    nonisolated var token: String? {
        lock.lock()
        defer { lock.unlock() }
        return cachedToken
    }

    /// Validates a token restored from the Keychain and fills in `currentUser`.
    /// Call once at launch.
    ///
    /// `init` can only say a token *exists*. Tokens last 30 days and
    /// `logout_all` retires them early, so a restored one may already be dead —
    /// and without this check the app renders signed-in screens whose every
    /// request 401s. A 401 here logs out through `APIClient`'s handler; a
    /// network failure deliberately does not, so a launch offline keeps the
    /// session.
    @MainActor
    func restoreSession() async {
        defer { isRestoring = false }
        guard token != nil else { return }
        do {
            currentUser = try await APIClient.shared.get(path: "/api/v1/auth/me_token")
        } catch {
            // A dead token has already been cleared by APIClient's 401 handler.
        }
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

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainKey,
        ]
    }

    private func readTokenFromKeychain() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveTokenToKeychain(_ token: String) {
        var query = baseQuery()
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            // The in-memory token still works for this launch; only persistence
            // failed, so the next launch lands on the login screen.
            log.error("could not persist the token to the Keychain (OSStatus \(status))")
        }
    }

    private func deleteTokenFromKeychain() {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            log.error("could not remove the token from the Keychain (OSStatus \(status))")
        }
    }
}
