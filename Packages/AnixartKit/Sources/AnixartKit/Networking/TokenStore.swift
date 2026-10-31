import Foundation

/// Where the session token lives between launches.
///
/// Anixart issues a long-lived token from `auth/signIn` (and the social sign-in
/// endpoints). A password change replaces it; there is no scheduled refresh.
public protocol TokenStore: Sendable {
    func token() async -> String?
    func profileID() async -> Int?
    func save(token: String, profileID: Int) async throws
    /// Atomic compare-and-replace: a delayed password response must not overwrite
    /// a token belonging to a newer sign-in (even to the same profile).
    func replace(token: String, profileID: Int, expectedToken: String) async throws -> Bool
    func clear() async throws
}

/// Non-persistent store, for tests and previews.
public actor InMemoryTokenStore: TokenStore {
    private var storedToken: String?
    private var storedProfileID: Int?

    public init(token: String? = nil, profileID: Int? = nil) {
        self.storedToken = token
        self.storedProfileID = profileID
    }

    public func token() async -> String? { storedToken }
    public func profileID() async -> Int? { storedProfileID }

    public func save(token: String, profileID: Int) async throws {
        storedToken = token
        storedProfileID = profileID
    }

    public func replace(token: String, profileID: Int, expectedToken: String) async throws -> Bool {
        guard storedToken == expectedToken, storedProfileID == profileID else { return false }
        storedToken = token
        return true
    }

    public func clear() async throws {
        storedToken = nil
        storedProfileID = nil
    }
}
