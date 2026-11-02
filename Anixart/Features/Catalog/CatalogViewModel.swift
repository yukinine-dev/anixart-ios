import Foundation
import AnixartKit

/// Catalogue tab: browses `filter/{page}` and switches to `search/releases/{page}`
/// as soon as there is a query, which is how the Android app behaves.
@MainActor
@Observable
final class CatalogViewModel {
    var query = "" {
        didSet { if query != oldValue { inputRevision += 1; closeVoiceSearch() } }
    }
    var searchScope: SearchScope = .all {
        didSet { if searchScope != oldValue { inputRevision += 1; closeVoiceSearch() } }
    }
    private(set) var filter = FilterRequest()
    private(set) var hasAppliedFilter: Bool

    private(set) var browse: Paginator<Release>
    private var searchModel: ReleaseSearchModel?
    let viewer: ProfileViewerKey
    private let session: SessionController
    private(set) var voiceInput: VoiceSearchModel?
    private var voiceContextIsActive = false
    private var inputRevision = 0
    let history: ReleaseSearchHistoryStore?
    @ObservationIgnored private let voiceServiceFactory: @MainActor () -> any VoiceInputService
    @ObservationIgnored private var voiceStartTask: Task<Void, Never>?

    init(session: SessionController, filter: FilterRequest = FilterRequest(), query: String = "", searchScope: SearchScope = .all,
         hasAppliedFilter: Bool = false, history: ReleaseSearchHistoryStore? = nil,
         voiceServiceFactory: (@MainActor () -> any VoiceInputService)? = nil) {
        self.session = session
        self.viewer = session.viewerKey
        self.filter = filter.normalized
        self.query = query
        self.searchScope = searchScope
        self.hasAppliedFilter = hasAppliedFilter
        self.history = history
        self.browse = Self.makePaginator(session: session, viewer: session.viewerKey, filter: filter.normalized)
        self.voiceServiceFactory = voiceServiceFactory ?? { SystemVoiceInputService() }
    }

    var hasCurrentViewer: Bool { viewer == session.viewerKey }
    var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isShowingSearch: Bool { !normalizedQuery.isEmpty }
    var isVoiceSearchAvailable: Bool { hasCurrentViewer && voiceContextIsActive && query.isEmpty }

    func setVoiceSearchActive(_ active: Bool) {
        guard voiceContextIsActive != active else { return }
        voiceContextIsActive = active
        if !active { closeVoiceSearch() }
    }

    func beginVoiceSearch() {
        guard isVoiceSearchAvailable, voiceInput == nil else { return }
        let revision = inputRevision
        let input = VoiceSearchModel(service: voiceServiceFactory(), isContextCurrent: { [weak self] in
            guard let self else { return false }
            return self.hasCurrentViewer && self.voiceContextIsActive && self.inputRevision == revision
        }, onText: { [weak self] text in
            guard let self, self.hasCurrentViewer, self.voiceContextIsActive, self.inputRevision == revision else { return }
            self.query = text
            self.rememberSearch()
            self.closeVoiceSearch()
        })
        voiceInput = input
        voiceStartTask = Task { await input.start() }
    }

    func retryVoiceSearch(ifCurrent expected: VoiceSearchModel? = nil) {
        if let expected, voiceInput !== expected { return }
        guard isVoiceSearchAvailable, let voiceInput else { return }
        voiceStartTask?.cancel()
        voiceStartTask = Task { await voiceInput.start() }
    }

    func closeVoiceSearch(ifCurrent expected: VoiceSearchModel? = nil) {
        if let expected, voiceInput !== expected { return }
        voiceInput?.cancel()
        voiceStartTask?.cancel()
        voiceStartTask = nil
        voiceInput = nil
    }

    /// Never show rows (or navigate using their account fields) for an older query
    /// during the debounce, or for a viewer that has signed out.
    var currentSearch: ReleaseSearchModel? {
        guard hasCurrentViewer, let searchModel,
              searchModel.query == normalizedQuery, searchModel.scope == searchScope else { return nil }
        return searchModel
    }

    var activeFilterCount: Int { filter.activeConstraintCount }
    var searchKey: ReleaseSearchKey { ReleaseSearchKey(query: normalizedQuery, scope: searchScope, viewer: viewer) }

    private var currentHistory: ReleaseSearchHistoryStore? {
        guard hasCurrentViewer, let history, history.profileID == viewer.account?.profileID else { return nil }
        return history
    }

    func rememberSearch() {
        currentHistory?.remember(query: normalizedQuery, scope: searchScope)
    }

    func useHistory(_ entry: ReleaseSearchHistoryStore.Entry) {
        guard let history = currentHistory,
              let saved = history.entries.first(where: { $0.id == entry.id }) else { return }
        searchScope = saved.scope
        query = saved.query
        rememberSearch()
    }

    @discardableResult
    func removeHistoryEntry(id: String) -> Bool {
        guard let history = currentHistory else { return false }
        return history.remove(id: id)
    }

    @discardableResult
    func clearHistory() -> Bool {
        guard let history = currentHistory, !history.entries.isEmpty else { return false }
        history.clear()
        return true
    }

    /// Explicit Apply switches contexts even when the normalized filter itself
    /// is unchanged. Filter fields never travel in search/releases requests.
    func apply(filter newFilter: FilterRequest) {
        let normalized = newFilter.normalized
        guard hasCurrentViewer, normalized.validationMessage == nil else { return }
        inputRevision += 1
        closeVoiceSearch()
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
        inputRevision += 1
        closeVoiceSearch()
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
