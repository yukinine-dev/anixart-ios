import Foundation
import Security

/// Keychain-backed `TokenStore`.
///
/// The token is the whole session, so it belongs in the keychain rather than
/// `UserDefaults` (where the Android app's `Prefs` equivalent keeps it). The
/// profile id is not a secret but is stored alongside so the two cannot drift apart.
public actor KeychainTokenStore: TokenStore {
    public enum KeychainError: Error, Sendable {
        case unexpectedStatus(OSStatus)
    }

    private let service: String
    private let account: String
    private var cached: (token: String, profileID: Int)??

    public init(service: String = "app.anixart.session", account: String = "token") {
        self.service = service
        self.account = account
    }

    public func token() async -> String? {
        entry()?.token
    }

    public func profileID() async -> Int? {
        entry()?.profileID
    }

    public func save(token: String, profileID: Int) async throws {
        try write(token: token, profileID: profileID)
    }

    public func replace(token: String, profileID: Int, expectedToken: String) async throws -> Bool {
        guard let current = entry(), current.token == expectedToken, current.profileID == profileID else { return false }
        // No suspension between checking the old entry and writing its replacement.
        try write(token: token, profileID: profileID)
        return true
    }

    private func write(token: String, profileID: Int) throws {
        let payload = try JSONEncoder().encode(StoredSession(token: token, profileID: profileID))
        var query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: payload,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = payload
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
        cached = .some((token, profileID))
    }

    public func clear() async throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
        cached = .some(nil)
    }

    // MARK: - Internals

    private struct StoredSession: Codable {
        var token: String
        var profileID: Int
    }

    private func entry() -> (token: String, profileID: Int)? {
        if let cached { return cached }
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let session = try? JSONDecoder().decode(StoredSession.self, from: data)
        else {
            cached = .some(nil)
            return nil
        }
        let value = (session.token, session.profileID)
        cached = .some(value)
        return value
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
