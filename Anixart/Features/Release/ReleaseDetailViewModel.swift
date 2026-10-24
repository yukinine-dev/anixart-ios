import Foundation
import AnixartKit

@MainActor
@Observable
final class ReleaseDetailViewModel {
    private(set) var release: Release?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Set when an action needed a session the user does not have.
    private(set) var actionError: String?

    private let releaseID: Int
    private let client: AnixartClient
    private let session: SessionController

    init(releaseID: Int, preloaded: Release?, client: AnixartClient, session: SessionController) {
        self.releaseID = releaseID
        self.release = preloaded
        self.client = client
        self.session = session
    }

    var isSignedIn: Bool { session.isSignedIn }

    /// `extended_mode` brings related releases, recommendations and the first
    /// comments in the same response, so the detail screen needs one request.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await client.send(ReleaseEndpoints.release(id: releaseID, extended: true))
            release = response.release ?? release
        } catch {
            // Keep a preloaded release on screen; only report when there is nothing.
            if release == nil {
                errorMessage = Paginator<Release>.message(for: error)
            }
        }
        isLoading = false
    }

    // MARK: - Actions
    //
    // Each of these updates the local copy first so the UI reacts immediately,
    // then reverts if the server disagrees.

    func setList(_ status: ProfileListStatus?) async {
        guard requireSession() else { return }
        guard var current = release else { return }
        let previous = current.profileListStatus

        current.profileListStatus = status?.rawValue
        release = current

        do {
            if let status {
                try await client.send(BookmarkEndpoints.addToList(releaseID: releaseID, status: status))
            } else if let previous, let old = ProfileListStatus(rawValue: previous) {
                try await client.send(BookmarkEndpoints.removeFromList(releaseID: releaseID, status: old))
            }
            await session.refreshProfile()
        } catch {
            current.profileListStatus = previous
            release = current
            actionError = Paginator<Release>.message(for: error)
        }
    }

    func toggleFavorite() async {
        guard requireSession() else { return }
        guard var current = release else { return }
        let wasFavorite = current.isFavorite ?? false

        current.isFavorite = !wasFavorite
        release = current

        do {
            if wasFavorite {
                try await client.send(BookmarkEndpoints.removeFavorite(releaseID: releaseID))
            } else {
                try await client.send(BookmarkEndpoints.addFavorite(releaseID: releaseID))
            }
        } catch {
            current.isFavorite = wasFavorite
            release = current
            actionError = Paginator<Release>.message(for: error)
        }
    }

    func vote(_ score: ReleaseVote) async {
        guard requireSession() else { return }
        do {
            try await client.send(ReleaseEndpoints.vote(releaseID: releaseID, score: score))
            // The aggregate grade changes server-side, so refetch rather than guess.
            await load()
        } catch {
            actionError = Paginator<Release>.message(for: error)
        }
    }

    func removeVote() async {
        guard requireSession() else { return }
        do {
            try await client.send(ReleaseEndpoints.deleteVote(releaseID: releaseID))
            await load()
        } catch {
            actionError = Paginator<Release>.message(for: error)
        }
    }

    func dismissActionError() {
        actionError = nil
    }

    private func requireSession() -> Bool {
        guard session.isSignedIn else {
            session.promptSignIn()
            return false
        }
        return true
    }
}
