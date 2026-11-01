import Foundation
import AnixartKit

/// Catalogue tab: browses `filter/{page}` and switches to `search/releases/{page}`
/// as soon as there is a query, which is how the Android app behaves.
@MainActor
@Observable
final class CatalogViewModel {
    var query = ""
    var searchScope: SearchScope = .all
    private(set) var filter = FilterRequest()
    private(set) var hasAppliedFilter: Bool

    private(set) var browse: Paginator<Release>
    private var searchModel: ReleaseSearchModel?
    let viewer: ProfileViewerKey
    private let session: SessionController

    init(session: SessionController, filter: FilterRequest = FilterRequest(), query: String = "", searchScope: SearchScope = .all, hasAppliedFilter: Bool = false) {
        self.session = session
        self.viewer = session.viewerKey
        self.filter = filter.normalized
        self.query = query
        self.searchScope = searchScope
        self.hasAppliedFilter = hasAppliedFilter
        self.browse = Self.makePaginator(session: session, viewer: session.viewerKey, filter: filter.normalized)
    }

    var hasCurrentViewer: Bool { viewer == session.viewerKey }
    var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isShowingSearch: Bool { !normalizedQuery.isEmpty }

    /// Never show rows (or navigate using their account fields) for an older query
    /// during the debounce, or for a viewer that has signed out.
    var currentSearch: ReleaseSearchModel? {
        guard hasCurrentViewer, let searchModel,
              searchModel.query == normalizedQuery, searchModel.scope == searchScope else { return nil }
        return searchModel
    }

    var activeFilterCount: Int { filter.activeConstraintCount }
    var searchKey: ReleaseSearchKey { ReleaseSearchKey(query: normalizedQuery, scope: searchScope, viewer: viewer) }

    /// Explicit Apply switches contexts even when the normalized filter itself
    /// is unchanged. Filter fields never travel in search/releases requests.
    func apply(filter newFilter: FilterRequest) {
        let normalized = newFilter.normalized
        guard hasCurrentViewer, normalized.validationMessage == nil else { return }
        let needsNewBrowse = normalized != filter || isShowingSearch || searchModel != nil
        query = ""
        searchModel?.invalidate()
        searchModel = nil
        hasAppliedFilter = true
        filter = normalized
        if needsNewBrowse { browse = Self.makePaginator(session: session, viewer: viewer, filter: filter) }
    }

    func resetFilter() {
        // Reset only the general filter, not a running title search or device
        // HomePreferences. A reset while searching must not dispatch a new search.
        guard hasCurrentViewer, filter != FilterRequest() else { return }
        filter = FilterRequest()
        browse = Self.makePaginator(session: session, viewer: viewer, filter: filter)
    }

    /// Debounced search, driven by the view with `.task(id: model.query)`.
    func search() async {
        guard hasCurrentViewer, !Task.isCancelled else { return }
        guard isShowingSearch else {
            searchModel?.invalidate()
            searchModel = nil
            return
        }
        if currentSearch == nil {
            searchModel = ReleaseSearchModel(query: normalizedQuery, scope: searchScope, session: session)
        }
        // Capture this result set, not a mutable property that a later keystroke
        // may replace before its first page starts loading.
        let results = searchModel
        await results?.loadFirstPageIfNeeded()
    }

    private static func makePaginator(session: SessionController, viewer: ProfileViewerKey, filter: FilterRequest) -> Paginator<Release> {
        let request = viewer.account == nil ? filter.withoutProfileListExclusions : filter
        return Paginator(rawPageSize: 25) { page in
            try await session.sendViewerRequest(CatalogEndpoints.filter(request, page: page), for: viewer)
        }
    }
}

struct ReleaseSearchKey: Equatable {
    let query: String
    let scope: SearchScope
    let viewer: ProfileViewerKey
}
