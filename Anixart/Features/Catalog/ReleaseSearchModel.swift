import Foundation
import AnixartKit

/// Unlike filter results, release search has no paging envelope. The original
/// ReleaseSearchPresenter requests another page only after 25 raw results and
/// reads the franchise suggestion from page zero.
@MainActor
@Observable
final class ReleaseSearchModel {
    let query: String
    let scope: SearchScope
    let viewer: ProfileViewerKey
    private let session: SessionController

    private(set) var items: [Release] = []
    private(set) var related: Related?
    private(set) var state: Paginator<Release>.LoadState = .idle
    private(set) var hasMore = true
    private(set) var failedPage: Int?
    private var hasLoadedFirstPage = false
    private var nextPage = 0
    private var generation = 0
    private var isInvalidated = false

    init(query: String, scope: SearchScope = .all, session: SessionController) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.scope = scope
        self.session = session
        self.viewer = session.viewerKey
    }

    var hasCurrentViewer: Bool { viewer == session.viewerKey }
    var isLoading: Bool { state == .loading }
    var errorMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    /// An explicit switch to filter results retires this whole result set, even
    /// if its URLSession task returns late without observing view cancellation.
    func invalidate() {
        generation += 1
        isInvalidated = true
        items = []
        related = nil
        state = .idle
        hasMore = false
        failedPage = nil
    }

    func loadFirstPageIfNeeded(debounce: Bool = true) async {
        guard !hasLoadedFirstPage, state == .idle else { return }
        await reload(debounce: debounce)
    }

    /// A refresh keeps visible results until the replacement page succeeds.
    func reload(debounce: Bool = false) async {
        guard !isInvalidated, hasCurrentViewer, !query.isEmpty, !Task.isCancelled else { return }
        generation += 1
        await fetch(page: 0, generation: generation, debounce: debounce)
    }

    func loadNextPage() async {
        guard hasLoadedFirstPage, hasMore, state == .idle else { return }
        await fetch(page: nextPage, generation: generation)
    }

    func retry() async {
        guard state != .loading else { return }
        if failedPage == 0 || !hasLoadedFirstPage { await reload() }
        else { await fetch(page: nextPage, generation: generation) }
    }

    private func fetch(page: Int, generation token: Int, debounce: Bool = false) async {
        guard !isInvalidated, hasCurrentViewer, !Task.isCancelled else { return }
        state = .loading
        failedPage = nil
        do {
            if debounce { try await Task.sleep(for: .milliseconds(350)) }
            try Task.checkCancellation()
            guard token == generation, !isInvalidated, hasCurrentViewer else { return }
            let response = try await session.sendViewerRequest(
                CatalogEndpoints.searchReleases(query, page: page, scope: scope), for: viewer
            )
            guard let releases = response.releases else {
                throw AnixartError.decoding(message: "Ответ не содержит результаты поиска", path: "search/releases/\(page)")
            }
            try Task.checkCancellation()
            guard token == generation, hasCurrentViewer else { return }
            if page == 0 {
                items = []
                related = response.related
                hasLoadedFirstPage = true
            }
            var seen = Set(items.map(\.id))
            items.append(contentsOf: releases.filter { seen.insert($0.id).inserted })
            // Use the raw count, not the deduplicated count: repeats across pages
            // must not turn a full server page into a false end-of-results.
            hasMore = releases.count >= 25
            nextPage = page + 1
            state = .idle
        } catch {
            guard token == generation else { return }
            if !hasCurrentViewer || ProfileRequestFailure.isCancellation(error) {
                state = .idle
                return
            }
            failedPage = page
            state = .failed(Paginator<Release>.message(for: error))
        }
    }
}
