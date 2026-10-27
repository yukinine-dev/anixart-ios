import Foundation
import os
import AnixartKit

/// Owns "who is signed in" for the whole app.
///
/// Anixart's token never expires on a schedule, so there is no refresh loop here:
/// the token is loaded once at launch and only changes on sign-in, sign-out, or a
/// server-side invalidation (which surfaces as an API error on the next call).
@MainActor
@Observable
final class SessionController {
    private static let log = Logger(subsystem: "app.anixart.client", category: "config")

    enum State: Equatable {
        case loading
        case guest
        case signedIn(profileID: Int)
    }

    private(set) var state: State = .loading
    private(set) var profile: Profile?
    private(set) var unreadNotifications = 0

    /// Drives the sign-in sheet owned by `RootView`. Any screen that reaches an
    /// authenticated endpoint sets this instead of presenting its own copy.
    var isPresentingAuth = false

    private let client: AnixartClient
    private let tokenStore: any TokenStore

    init(client: AnixartClient, tokenStore: any TokenStore) {
        self.client = client
        self.tokenStore = tokenStore
    }

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    var currentProfileID: Int? {
        if case .signedIn(let id) = state { return id }
        return nil
    }

    /// Reads the stored token and, if there is one, fetches the owning profile.
    func restore() async {
        guard let profileID = await tokenStore.profileID(),
              await tokenStore.token() != nil
        else {
            state = .guest
            return
        }
        state = .signedIn(profileID: profileID)
        await refreshProfile()
        await refreshNotificationCount()
    }

    /// Picks up the host list and feature flags the server advertises.
    ///
    /// Best-effort: the hardcoded fallback host works on its own, so a failure here
    /// must not block the UI.
    func loadRemoteConfiguration() async {
        if let urls = try? await client.send(ConfigEndpoints.urls()) {
            await client.apply(urls)
        }
        // `config/toggles` was never fetched, which is why the Kodik path had
        // nothing to work with: `kodikAdIframeUrl`, `kodikVideoLinksUrl` and
        // `kodikIframeAd` all live here, and the APK reads them from the same
        // place. The model was generated at the start of this port; nobody had
        // asked the server for it.
        toggles = try? await client.send(ConfigEndpoints.toggles())
        // Said out loud, because its absence is silent everywhere else: without
        // it the Kodik path falls back to the bare page, and the only sign is a
        // player that does not open.
        if let base = toggles?.kodikAdIframeUrl {
            Self.log.notice("config toggles loaded, kodik wrapper \(base, privacy: .public)")
        } else if toggles == nil {
            Self.log.error("config toggles did not load; the Kodik wrapper is unavailable")
        } else {
            Self.log.notice("config toggles loaded, but it names no kodik wrapper")
        }
    }

    /// Server-side feature flags, including everything the Kodik playback path
    /// needs. Absent until `loadRemoteConfiguration()` has run, and absent for
    /// good if it failed -- the rest of the app works without it.
    private(set) var toggles: TogglesResponse?

    func signIn(login: String, password: String) async throws {
        let response = try await client.send(AuthEndpoints.signIn(login: login, password: password))
        try await adopt(token: response.profileToken?.token, profile: response.profile)
    }

    func signInWithVK(accessToken: String) async throws {
        let response = try await client.send(AuthEndpoints.signInWithVK(accessToken: accessToken))
        try await adopt(token: response.profileToken?.token, profile: response.profile)
    }

    func signInWithGoogle(idToken: String) async throws {
        let response = try await client.send(AuthEndpoints.signInWithGoogle(idToken: idToken))
        try await adopt(token: response.profileToken?.token, profile: response.profile)
    }

    func signInWithYandex(accessToken: String) async throws {
        let response = try await client.send(AuthEndpoints.signInWithYandex(accessToken: accessToken))
        try await adopt(token: response.profileToken?.token, profile: response.profile)
    }

    /// Finishes the emailed-code step of sign-up or social registration.
    func verify(
        login: String,
        email: String,
        password: String = "",
        hash: String,
        code: String
    ) async throws {
        let response = try await client.send(
            AuthEndpoints.verify(login: login, email: email, password: password, hash: hash, code: code)
        )
        try await adopt(token: response.profileToken?.token, profile: response.profile)
    }

    /// Asks the root view to present sign-in.
    func promptSignIn() {
        isPresentingAuth = true
    }

    func signOut() async {
        try? await tokenStore.clear()
        profile = nil
        unreadNotifications = 0
        state = .guest
    }

    func refreshProfile() async {
        guard let id = currentProfileID else { return }
        if let response = try? await client.send(ProfileEndpoints.profile(id: id)) {
            profile = response.profile
        }
    }

    func refreshNotificationCount() async {
        guard isSignedIn else { return }
        if let response = try? await client.send(NotificationEndpoints.unreadCount()) {
            unreadNotifications = response.count ?? 0
        }
    }

    /// Called after the notifications screen is opened.
    func clearNotificationBadge() {
        unreadNotifications = 0
    }

    private func adopt(token: String?, profile: Profile?) async throws {
        guard let token, let profile else {
            // A 0 code with no token means the account needs the email code first;
            // the caller drives that flow, so surface it rather than guessing.
            throw AnixartError.api(code: AnixartStatus.failed, path: "auth")
        }
        try await tokenStore.save(token: token, profileID: profile.id)
        self.profile = profile
        state = .signedIn(profileID: profile.id)
        isPresentingAuth = false
        await refreshNotificationCount()
    }
}
