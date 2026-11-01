import Foundation
import AnixartKit

/// One immutable filter/viewer pair. A tab or session change creates a new model,
/// so neither a late page nor an open list picker can borrow a later login token.
@MainActor
@Observable
final class ReleaseFeedModel {
    let filter: FilterRequest
    let viewer: ProfileViewerKey
    let paginator: Paginator<Release>
    private let session: SessionController
    private(set) var isPerformingAction = false
    private(set) var actionError: String?
    private let actionResource = ProfileResource<Release>()
    private var actionReleaseID: Int?

    init(filter: FilterRequest, session: SessionController, paginator: Paginator<Release>? = nil) {
        self.filter = filter
        self.session = session
        let viewer = session.viewerKey
        self.viewer = viewer
        let request = viewer.account == nil ? filter.withoutProfileListExclusions : filter
        if let paginator {
            self.paginator = paginator
        } else {
            self.paginator = Paginator(rawPageSize: 25) { page in
                try await session.sendViewerRequest(CatalogEndpoints.filter(request, page: page), for: viewer)
            }
        }
    }

    var hasCurrentViewer: Bool { viewer == session.viewerKey }
    var actionRelease: Release? {
        guard hasCurrentViewer, let actionReleaseID, let value = actionResource.value,
              value.id == actionReleaseID else { return nil }
        return value
    }
    var isLoadingActionRelease: Bool { actionResource.isLoading }
    var actionLoadError: String? { actionResource.errorMessage }

    func dismissActionError() { actionError = nil }

    /// Opening the shared overflow reads only the selected release for this
    /// viewer. This does not submit a favourite/list mutation or touch HomePrefs.
    func loadActionRelease(releaseID: Int) async {
        guard hasCurrentViewer, !Task.isCancelled, !isPerformingAction else { return }
        if actionReleaseID != releaseID { actionResource.reset() }
        actionReleaseID = releaseID
        actionError = nil
        await readActionRelease(releaseID: releaseID, allowDuringAction: false)
    }

    /// Radio selection is a no-op for the same known status. Only an explicit
    /// nil choice removes a list; failed/unconfirmed writes keep their baseline.
    @discardableResult
    func setList(_ status: ProfileListStatus?, releaseID: Int) async -> Bool {
        guard hasCurrentViewer, !Task.isCancelled, !isPerformingAction else { return false }
        guard let release = currentReleaseForAction(releaseID) else { return false }
        if release.profileListStatus == status?.rawValue { return true }
        guard let account = viewer.account else { session.promptSignIn(); return false }
        let endpoint: Endpoint<StatusResponse>
        if let status {
            endpoint = BookmarkEndpoints.addToList(releaseID: releaseID, status: status)
        } else if let old = release.listStatus {
            endpoint = BookmarkEndpoints.removeFromList(releaseID: releaseID, status: old)
        } else { return false }

        return await perform(endpoint, change: .list(status), current: release, account: account)
    }

    @discardableResult
    func toggleFavorite(releaseID: Int) async -> Bool {
        guard hasCurrentViewer, !Task.isCancelled, !isPerformingAction else { return false }
        guard let account = viewer.account else { session.promptSignIn(); return false }
        guard let release = currentReleaseForAction(releaseID) else { return false }
        let wasFavorite = release.isFavorite == true
        let endpoint = wasFavorite ? BookmarkEndpoints.removeFavorite(releaseID: releaseID)
                                   : BookmarkEndpoints.addFavorite(releaseID: releaseID)
        return await perform(endpoint, change: .favorite(!wasFavorite), current: release, account: account)
    }

    private func currentReleaseForAction(_ id: Int) -> Release? {
        guard id > 0 else { return nil }
        if let actionReleaseID {
            guard actionReleaseID == id, !isLoadingActionRelease, actionLoadError == nil else { return nil }
            return actionRelease
        }
        guard let release = paginator.items.first(where: { $0.id == id }) else {
            actionError = "Список изменился. Откройте действия с релизом заново."
            return nil
        }
        return release
    }

    private func readActionRelease(releaseID: Int, allowDuringAction: Bool) async {
        guard hasCurrentViewer, !Task.isCancelled, releaseID > 0,
              allowDuringAction || !isPerformingAction else { return }
        await actionResource.load {
            let response = try await session.sendViewerRequest(ReleaseEndpoints.release(id: releaseID, extended: true), for: viewer)
            guard let release = response.release, release.id == releaseID else {
                throw AnixartError.decoding(message: "Ответ не содержит релиз", path: "release/\(releaseID)")
            }
            return release
        }
    }

    private func perform(_ endpoint: Endpoint<StatusResponse>, change: Change, current: Release, account: ProfileAccountKey) async -> Bool {
        guard hasCurrentViewer, session.accountKey == account, !Task.isCancelled, !isPerformingAction else { return false }
        isPerformingAction = true
        actionError = nil
        if actionReleaseID == current.id { actionResource.adopt(current) }
        defer { isPerformingAction = false }
        do {
            try await session.sendConfirmedAccountRequest(endpoint, for: account)
            if var selected = actionRelease, selected.id == current.id {
                change.apply(to: &selected)
                actionResource.adopt(selected)
            }
            // Update only the acknowledged field on the latest row, not unrelated
            // flags/metadata from the snapshot taken before a suspended mutation.
            if var row = paginator.items.first(where: { $0.id == current.id }) {
                change.apply(to: &row)
                paginator.update(row)
            }
            if case .list(let status?) = change, filter.profileListExclusions?.contains(status.rawValue) == true {
                paginator.remove(id: current.id)
            }
            // Invalidate older pages before any supplementary read can suspend.
            await paginator.reload()
            if actionReleaseID == current.id { await readActionRelease(releaseID: current.id, allowDuringAction: true) }
            await session.refreshProfile(for: account)
            return hasCurrentViewer && !Task.isCancelled
        } catch {
            if hasCurrentViewer, !ProfileRequestFailure.isCancellation(error) {
                actionError = Paginator<Release>.message(for: error)
            }
            return false
        }
    }

    private enum Change {
        case list(ProfileListStatus?)
        case favorite(Bool)

        func apply(to release: inout Release) {
            switch self {
            case .list(let status): release.profileListStatus = status?.rawValue
            case .favorite(let value): release.isFavorite = value
            }
        }
    }
}

struct ReleaseFeedKey: Equatable {
    let filter: FilterRequest
    let viewer: ProfileViewerKey
}
