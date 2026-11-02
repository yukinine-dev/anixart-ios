import Foundation
import AnixartKit

/// An account snapshot for one bookmarks tab/sort. Its rows and actions cannot
/// borrow a token from a later login while a navigation or request is in flight.
@MainActor
@Observable
final class BookmarkReleaseListModel {
    let kind: BookmarkReleaseList.Kind
    let sort: BookmarkSort
    let viewer: ProfileViewerKey
    let paginator: Paginator<Release>
    private let session: SessionController
    private(set) var removingIDs = Set<Int>()
    private(set) var actionError: String?

    init(kind: BookmarkReleaseList.Kind, sort: BookmarkSort, session: SessionController) {
        self.kind = kind
        self.sort = sort
        self.session = session
        let viewer = session.viewerKey
        self.viewer = viewer
        // BookmarksTabPresenter stops on a raw page shorter than 25, including
        // servers that return zero/absent page-count metadata.
        paginator = Paginator(rawPageSize: 25) { page in
            switch kind {
            case .favorites:
                return try await session.sendViewerRequest(BookmarkEndpoints.favorites(page: page, sort: sort), for: viewer)
            case .history:
                return try await session.sendViewerRequest(BookmarkEndpoints.history(page: page), for: viewer)
            case .list(let status):
                return try await session.sendViewerRequest(BookmarkEndpoints.list(status, page: page, sort: sort), for: viewer)
            }
        }
    }

    var hasCurrentViewer: Bool { viewer == session.viewerKey }

    func reload() async {
        guard hasCurrentViewer else { return }
        await paginator.reload()
    }

    func removeFromHistory(releaseID: Int) async {
        guard kind == .history, hasCurrentViewer, let account = viewer.account,
              paginator.items.contains(where: { $0.id == releaseID }), !removingIDs.contains(releaseID) else { return }
        removingIDs.insert(releaseID)
        actionError = nil
        defer { removingIDs.remove(releaseID) }
        do {
            try await session.sendConfirmedAccountRequest(BookmarkEndpoints.removeFromHistory(releaseID: releaseID), for: account)
            // Deleting shifts positional pages; a late page from before the delete
            // must not put the removed title back or skip a later entry.
            await paginator.removeAndReload(id: releaseID)
            await session.refreshProfile(for: account)
        } catch {
            if hasCurrentViewer, !ProfileRequestFailure.isCancellation(error) {
                actionError = Paginator<Release>.message(for: error)
            }
        }
    }
}

struct BookmarkReleaseListKey: Equatable {
    let kind: BookmarkReleaseList.Kind
    let sort: BookmarkSort
    let viewer: ProfileViewerKey
}
