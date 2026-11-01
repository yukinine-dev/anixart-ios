import Foundation
import os
import AnixartKit

/// Owns "who is signed in" for the whole app.
///
/// Anixart's token never expires on a schedule, so there is no refresh loop here:
/// the token is loaded once at launch and changes on sign-in, sign-out, password
/// changes, or server-side invalidation (an API error on the next call).
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
    /// Also changes when only the cover/showcase changed and the Profile is equal.
    private(set) var profileRevision = 0
    private(set) var sessionRevision = 0

    /// Drives the sign-in sheet owned by `RootView`. Any screen that reaches an
    /// authenticated endpoint sets this instead of presenting its own copy.
    var isPresentingAuth = false

    private let client: AnixartClient
    private let tokenStore: any TokenStore
    private var profileGeneration = 0
    private var notificationGeneration = 0
    private var isChangingSession = false
    @ObservationIgnored private var persistenceTail: Task<Void, Never>?

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

    var accountKey: ProfileAccountKey? {
        guard !isChangingSession, let id = currentProfileID else { return nil }
        return ProfileAccountKey(profileID: id, revision: sessionRevision)
    }

    /// Unlike an optional account, this also identifies the session of a guest.
    var viewerKey: ProfileViewerKey {
        ProfileViewerKey(account: accountKey, revision: sessionRevision)
    }

    /// An editor keeps the account it was opened for. Never send its draft with
    /// the token of a later sign-in, or apply an old response to the new account.
    @discardableResult
    func sendAccountRequest<Response: Decodable & Sendable>(
        _ endpoint: Endpoint<Response>, for account: ProfileAccountKey
    ) async throws -> Response {
        try Task.checkCancellation()
        guard accountKey == account else { throw CancellationError() }
        var scoped = endpoint
        // Public validation endpoints must stay token-free, even when their
        // result belongs to a signed-in editor.
        switch endpoint.auth {
        case .none: break
        case .optional, .required, .matchingToken:
            guard let token = await tokenStore.token(), !token.isEmpty, accountKey == account else {
                throw CancellationError()
            }
            scoped.auth = .matchingToken(token)
        }
        try Task.checkCancellation()
        do {
            let response = try await client.send(scoped)
            try Task.checkCancellation()
            guard accountKey == account else { throw CancellationError() }
            return response
        } catch {
            guard accountKey == account else { throw CancellationError() }
            throw error
        }
    }

    /// Public reads also keep the viewer that opened a screen, rather than
    /// borrowing a token from a later sign-in.
    func sendViewerRequest<Response: Decodable & Sendable>(
        _ endpoint: Endpoint<Response>, for viewer: ProfileViewerKey
    ) async throws -> Response {
        try Task.checkCancellation()
        guard viewerKey == viewer, !isChangingSession else { throw CancellationError() }
        if let account = viewer.account { return try await sendAccountRequest(endpoint, for: account) }
        switch endpoint.auth {
        case .required, .matchingToken:
            throw AnixartError.notAuthenticated(path: endpoint.path)
        case .none, .optional: break
        }
        var publicEndpoint = endpoint
        publicEndpoint.auth = .none
        do {
            let response = try await client.send(publicEndpoint)
            try Task.checkCancellation()
            guard viewerKey == viewer, !isChangingSession else { throw CancellationError() }
            return response
        } catch {
            guard viewerKey == viewer, !isChangingSession else { throw CancellationError() }
            throw error
        }
    }

    /// A mutation must carry an explicit acknowledgement. An empty object is
    /// tolerated by optional read models, but must never discard an editor draft
    /// or be presented as a successful account change.
    @discardableResult
    func sendConfirmedAccountRequest<Response: AnixartResponse & Sendable>(
        _ endpoint: Endpoint<Response>, for account: ProfileAccountKey
    ) async throws -> Response {
        let response = try await sendAccountRequest(endpoint, for: account)
        guard response.code == AnixartStatus.successful else {
            throw AnixartError.decoding(message: "Сервер не подтвердил изменение", path: endpoint.path)
        }
        return response
    }

    /// Reads the stored token and, if there is one, fetches the owning profile.
    func restore() async {
        guard state == .loading, !Task.isCancelled else { return }
        let revision = sessionRevision
        await persistenceTail?.value
        guard revision == sessionRevision, !Task.isCancelled, !isChangingSession else { return }
        guard let profileID = await tokenStore.profileID(),
              profileID > 0, let token = await tokenStore.token(), !token.isEmpty
        else {
            if revision == sessionRevision, !Task.isCancelled { state = .guest }
            return
        }
        guard revision == sessionRevision, !Task.isCancelled, !isChangingSession else { return }
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
        try await authenticate {
            let response = try await client.send(AuthEndpoints.signIn(login: login, password: password))
            return (response.profileToken?.token, response.profile)
        }
    }

    func signInWithVK(accessToken: String) async throws {
        try await authenticate {
            let response = try await client.send(AuthEndpoints.signInWithVK(accessToken: accessToken))
            return (response.profileToken?.token, response.profile)
        }
    }

    func signInWithGoogle(idToken: String) async throws {
        try await authenticate {
            let response = try await client.send(AuthEndpoints.signInWithGoogle(idToken: idToken))
            return (response.profileToken?.token, response.profile)
        }
    }

    func signInWithYandex(accessToken: String) async throws {
        try await authenticate {
            let response = try await client.send(AuthEndpoints.signInWithYandex(accessToken: accessToken))
            return (response.profileToken?.token, response.profile)
        }
    }

    /// Finishes the emailed-code step of sign-up or social registration.
    func verify(
        login: String,
        email: String,
        password: String = "",
        hash: String,
        code: String
    ) async throws {
        try await authenticate {
            let response = try await client.send(
                AuthEndpoints.verify(login: login, email: email, password: password, hash: hash, code: code)
            )
            return (response.profileToken?.token, response.profile)
        }
    }

    /// Asks the root view to present sign-in.
    func promptSignIn() {
        isPresentingAuth = true
    }

    func signOut() async {
        sessionRevision += 1
        profileGeneration += 1
        notificationGeneration += 1
        isChangingSession = false
        isPresentingAuth = false
        profile = nil
        unreadNotifications = 0
        state = .guest
        profileRevision += 1
        // Queue the clear before yielding. A following sign-in's save cannot be
        // overtaken by a slow clear, nor can an old sign-in save after this clear.
        do { try await persist { try await self.tokenStore.clear() } }
        catch { Self.log.error("Could not clear the stored session") }
    }

    func refreshProfile(for expectedAccount: ProfileAccountKey? = nil) async {
        guard let account = accountKey, expectedAccount == nil || expectedAccount == account else { return }
        let id = account.profileID
        profileGeneration += 1
        let generation = profileGeneration
        defer {
            if accountKey == account, generation == profileGeneration,
               !Task.isCancelled { profileRevision += 1 }
        }
        if let response = try? await sendAccountRequest(ProfileEndpoints.profile(id: id), for: account),
           let updated = response.profile, updated.id == id,
           accountKey == account, generation == profileGeneration, !Task.isCancelled {
            profile = updated
        }
    }

    /// Password changes invalidate the old token. Persist the replacement before
    /// making another authenticated request, without losing the owning profile ID.
    private func replaceToken(_ token: String?, profileID: Int, expectedToken: String, revision: Int) async throws {
        guard revision == sessionRevision, currentProfileID == profileID else { throw CancellationError() }
        guard let token, !token.isEmpty else {
            throw AnixartError.decoding(message: "Сервер не вернул новый токен", path: "profile/preference/password/change")
        }
        let replaced = try await persist {
            guard revision == self.sessionRevision, self.currentProfileID == profileID else { throw CancellationError() }
            return try await self.tokenStore.replace(token: token, profileID: profileID, expectedToken: expectedToken)
        }
        guard replaced, revision == sessionRevision, currentProfileID == profileID else { throw CancellationError() }
        sessionRevision += 1
        profileGeneration += 1
        notificationGeneration += 1
        isChangingSession = false
    }

    @discardableResult
    func changePassword(current: String, new: String, for account: ProfileAccountKey) async throws -> ProfileAccountKey {
        try Task.checkCancellation()
        guard accountKey == account, let token = await tokenStore.token(), !token.isEmpty,
              accountKey == account else { throw CancellationError() }
        try Task.checkCancellation()
        let revision = account.revision
        let id = account.profileID
        isChangingSession = true
        defer { if revision == sessionRevision { isChangingSession = false } }
        var endpoint = ProfilePreferenceEndpoints.changePassword(current: current, new: new)
        endpoint.auth = .matchingToken(token)
        let response: ChangePasswordResponse
        // Once this mutation starts, keep receiving its response even if the
        // editor disappears: a successful response contains the only replacement
        // for the token the server has just invalidated.
        let mutation = Task { try await client.send(endpoint) }
        do { response = try await mutation.value }
        catch {
            guard revision == sessionRevision, currentProfileID == id else { throw CancellationError() }
            try Task.checkCancellation()
            throw error
        }
        // Do not abandon token persistence on view cancellation after a successful
        // mutation: the server has already invalidated the old token at this point.
        guard revision == sessionRevision, currentProfileID == id else { throw CancellationError() }
        guard response.code == AnixartStatus.successful else {
            try Task.checkCancellation()
            throw AnixartError.decoding(message: "Сервер не подтвердил изменение", path: endpoint.path)
        }
        try await replaceToken(response.token, profileID: id, expectedToken: token, revision: revision)
        guard let updatedAccount = accountKey else { throw CancellationError() }
        try Task.checkCancellation()
        await refreshProfile(for: updatedAccount)
        try Task.checkCancellation()
        guard accountKey == updatedAccount else { throw CancellationError() }
        return updatedAccount
    }

    func refreshNotificationCount() async {
        guard let account = accountKey else { return }
        notificationGeneration += 1
        let generation = notificationGeneration
        if let response = try? await sendAccountRequest(NotificationEndpoints.unreadCount(), for: account),
           accountKey == account, generation == notificationGeneration, !Task.isCancelled {
            unreadNotifications = response.count ?? 0
        }
    }

    /// A read acknowledgement is account-scoped and must succeed before the badge
    /// changes. A newer count/session response supersedes this request.
    func markNotificationsRead(for account: ProfileAccountKey) async throws {
        guard accountKey == account else { throw CancellationError() }
        notificationGeneration += 1
        let generation = notificationGeneration
        try await sendConfirmedAccountRequest(NotificationEndpoints.markAllRead(), for: account)
        guard accountKey == account, generation == notificationGeneration else { return }
        unreadNotifications = 0
    }

    /// Reserve a revision before the network call, not after it: an older login
    /// response must not undo a sign-out or a more recent login attempt.
    private func authenticate(_ fetch: () async throws -> (String?, Profile?)) async throws {
        try Task.checkCancellation()
        sessionRevision += 1
        profileGeneration += 1
        notificationGeneration += 1
        let revision = sessionRevision
        isChangingSession = true
        if state == .loading { state = .guest }
        defer { if revision == sessionRevision { isChangingSession = false } }
        let token: String?
        let profile: Profile?
        do { (token, profile) = try await fetch() }
        catch {
            guard revision == sessionRevision else { throw CancellationError() }
            try Task.checkCancellation()
            throw error
        }
        try Task.checkCancellation()
        guard revision == sessionRevision else { throw CancellationError() }
        try await adopt(token: token, profile: profile, revision: revision)
    }

    private func adopt(token: String?, profile: Profile?, revision: Int) async throws {
        guard let token, !token.isEmpty, let profile, profile.id > 0 else {
            // A 0 code with no token means the account needs the email code first;
            // the caller drives that flow, so surface it rather than guessing.
            throw AnixartError.api(code: AnixartStatus.failed, path: "auth")
        }
        let cancellation = SessionPersistenceCancellation()
        try await withTaskCancellationHandler {
            try await persist {
                guard revision == self.sessionRevision, !cancellation.isCancelled else { throw CancellationError() }
                let oldToken = await self.tokenStore.token()
                let oldProfileID = await self.tokenStore.profileID()
                guard revision == self.sessionRevision, !cancellation.isCancelled else { throw CancellationError() }
                try await self.tokenStore.save(token: token, profileID: profile.id)

                guard revision == self.sessionRevision, !cancellation.isCancelled else {
                    // This still owns the write queue. Restore the previous entry
                    // before a following sign-out/sign-in can write its own entry.
                    if let oldToken, !oldToken.isEmpty, let oldProfileID {
                        try await self.tokenStore.save(token: oldToken, profileID: oldProfileID)
                    } else { try await self.tokenStore.clear() }
                    throw CancellationError()
                }
                // Publish inside the same operation, without another suspension
                // between checking cancellation and committing the session.
                self.profile = profile
                self.profileRevision += 1
                self.state = .signedIn(profileID: profile.id)
                self.isChangingSession = false
                self.isPresentingAuth = false
            }
        } onCancel: { cancellation.cancel() }
        await refreshNotificationCount()
    }

    /// Serialize token writes, including stores whose async methods suspend.
    /// Unstructured tasks deliberately complete password-token persistence even
    /// when the editor's task is cancelled after the server has changed it.
    private func persist<Value: Sendable>(
        _ operation: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        let previous = persistenceTail
        let task = Task { @MainActor in
            await previous?.value
            return try await operation()
        }
        persistenceTail = Task { _ = try? await task.value }
        return try await task.value
    }
}

struct ProfileAccountKey: Equatable, Sendable {
    let profileID: Int
    let revision: Int

    var viewerKey: ProfileViewerKey { ProfileViewerKey(account: self, revision: revision) }
}

struct ProfileViewerKey: Equatable, Sendable {
    let account: ProfileAccountKey?
    let revision: Int
}

/// The token queue intentionally uses uncancelled tasks. Login (unlike a
/// completed password mutation) needs an explicit cancellation signal in it.
private final class SessionPersistenceCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
    }
}
