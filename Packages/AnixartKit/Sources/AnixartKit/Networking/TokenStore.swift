import Foundation

/// Where the session token lives between launches.
///
/// Anixart issues a long-lived token from `auth/signIn` (and the social sign-in
/// endpoints) and never rotates or refreshes it, so there is nothing to renew --
/// it is valid until the user signs out or the server invalidates it.
public protocol TokenStore: Sendable {
    func token() async -> String?
    func profileID() async -> Int?
    func save(token: String, profileID: Int) async throws
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

    public func clear() async throws {
        storedToken = nil
        storedProfileID = nil
    }
}
