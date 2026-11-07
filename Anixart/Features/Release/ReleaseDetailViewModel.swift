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
    private(set) var isPerformingAction = false

    private let releaseID: Int
    private let session: SessionController
    let viewer: ProfileViewerKey
    private var loadGeneration = 0

    init(releaseID: Int, preloaded: Release?, session: SessionController, viewer: ProfileViewerKey? = nil) {
        self.releaseID = releaseID
        self.release = preloaded?.id == releaseID ? preloaded : nil
        self.session = session
        self.viewer = viewer ?? session.viewerKey
    }

    var hasCurrentViewer: Bool { viewer == session.viewerKey }
    var isSignedIn: Bool { hasCurrentViewer && viewer.account != nil }

    func invalidate() {
        loadGeneration += 1
        release = nil
        isLoading = false
        isPerformingAction = false
        errorMessage = nil
        actionError = nil
    }

    /// `extended_mode` brings related releases, recommendations and the first
    /// comments in the same response, so the detail screen needs one request.
    func load() async {
        await load(allowDuringAction: false)
    }

    private func load(allowDuringAction: Bool) async {
        guard hasCurrentViewer, !Task.isCancelled, !isLoading,
              allowDuringAction || !isPerformingAction else { return }
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let response = try await session.sendViewerRequest(ReleaseEndpoints.release(id: releaseID, extended: true), for: viewer)
            guard let loaded = response.release, loaded.id == releaseID else {
                throw AnixartError.decoding(message: "Ответ не содержит релиз", path: "release/\(releaseID)")
            }
            guard generation == loadGeneration, hasCurrentViewer, !Task.isCancelled else { return }
            release = loaded
        } catch {
            guard generation == loadGeneration, hasCurrentViewer, !ProfileRequestFailure.isCancellation(error) else { return }
            // Keep the preload usable, but do not silently pass incomplete list
            // metadata off as a successfully loaded extended detail response.
            errorMessage = Paginator<Release>.message(for: error)
        }
    }

    // MARK: - Actions
    //
    // Each of these updates the local copy first so the UI reacts immediately,
    // then reverts if the server disagrees.

    func setList(_ status: ProfileListStatus?) async {
        guard hasCurrentViewer, !Task.isCancelled, let current = release else { return }
        guard current.profileListStatus != status?.rawValue else { return }
        let endpoint: Endpoint<StatusResponse>
        if let status {
            endpoint = BookmarkEndpoints.addToList(releaseID: releaseID, status: status)
        } else if let previous = current.profileListStatus, let old = ProfileListStatus(rawValue: previous) {
            endpoint = BookmarkEndpoints.removeFromList(releaseID: releaseID, status: old)
        } else { return }
        guard let account = beginAction() else { return }
        defer { isPerformingAction = false }
        let previous = current.profileListStatus

        release?.profileListStatus = status?.rawValue

        do {
            try await session.sendConfirmedAccountRequest(endpoint, for: account)
        } catch {
            guard hasCurrentViewer else { return }
            release?.profileListStatus = previous
            showActionError(error)
            return
        }
        // Only the write can roll back its optimistic field. Aggregate read
        // failure/cancellation is reported separately and keeps the acknowledgement.
        await load(allowDuringAction: true)
        await session.refreshProfile(for: account)
    }

    func toggleFavorite() async {
        guard let current = release, let account = beginAction() else { return }
        defer { isPerformingAction = false }
        let wasFavorite = current.isFavorite ?? false

        release?.isFavorite = !wasFavorite

        do {
            if wasFavorite {
                try await session.sendConfirmedAccountRequest(BookmarkEndpoints.removeFavorite(releaseID: releaseID), for: account)
            } else {
                try await session.sendConfirmedAccountRequest(BookmarkEndpoints.addFavorite(releaseID: releaseID), for: account)
            }
        } catch {
            guard hasCurrentViewer else { return }
            release?.isFavorite = wasFavorite
            showActionError(error)
            return
        }
        await load(allowDuringAction: true)
        await session.refreshProfile(for: account)
    }

    func vote(_ score: ReleaseVote) async {
        await changeVote(ReleaseEndpoints.vote(releaseID: releaseID, score: score), value: score.rawValue)
    }

    func removeVote() async {
        guard let vote = release?.yourVote, (1...5).contains(vote) else { return }
        await changeVote(ReleaseEndpoints.deleteVote(releaseID: releaseID), value: nil)
    }

    private func changeVote(_ endpoint: Endpoint<StatusResponse>, value: Int?) async {
        guard release != nil else { return }
        guard let account = beginAction() else { return }
        defer { isPerformingAction = false }
        do {
            try await session.sendConfirmedAccountRequest(endpoint, for: account)
            // Own stars are acknowledged even when the following aggregate read
            // fails. That read's failure remains visible on the detail screen.
            release?.yourVote = value
            // The aggregate grade changes server-side, so refetch rather than guess.
            await load(allowDuringAction: true)
            await session.refreshProfile(for: account)
        } catch {
            showActionError(error)
        }
    }

    func voteComment(_ comment: ReleaseComment, _ vote: CommentVote) async {
        guard hasCurrentViewer, comment.isDeleted != true, comment.canLike != false else { return }
        guard let account = beginAction() else { return }
        defer { isPerformingAction = false }
        do {
            try await session.sendConfirmedAccountRequest(CommentEndpoints.vote(commentID: comment.id, vote: vote), for: account)
            await load(allowDuringAction: true)
        } catch {
            showActionError(error)
        }
    }

    func dismissActionError() {
        actionError = nil
    }

    private func beginAction() -> ProfileAccountKey? {
        guard hasCurrentViewer, !Task.isCancelled, !isPerformingAction else { return nil }
        guard let account = viewer.account else {
            session.promptSignIn()
            return nil
        }
        isPerformingAction = true
        actionError = nil
        // An older detail load must not overwrite an optimistic edit.
        loadGeneration += 1
        isLoading = false
        return account
    }

    private func showActionError(_ error: any Error) {
        guard hasCurrentViewer, !ProfileRequestFailure.isCancellation(error) else { return }
        actionError = Paginator<Release>.message(for: error)
    }
}
