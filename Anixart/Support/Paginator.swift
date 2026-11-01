import Foundation
import AnixartKit

/// Drives one infinitely-scrolling list.
///
/// Requests are zero-based. Existing callers use their metadata strategy; known
/// browsing endpoints opt into raw page sizes because their metadata can be a
/// placeholder or final page index. Loading guards and generations keep duplicate
/// fetches and stale responses from overwriting newer results.
@MainActor
@Observable
final class Paginator<Item: Identifiable & Codable & Sendable> {
    enum LoadState: Equatable {
        case idle
        case loading
        case failed(String)
    }

    private(set) var items: [Item] = []
    private(set) var state: LoadState = .idle
    private(set) var hasMore = true
    private(set) var totalCount: Int?

    /// Fetches one page. Called with a zero-based page index.
    private let fetch: @Sendable (Int) async throws -> PageableResponse<Item>

    private var nextPage = 0
    private var generation = 0
    private var hasLoadedFirstPage = false
    private let continuesWithoutPageCount: Bool
    /// Opt-in for browsing APIs whose metadata is zero, a last-page index or
    /// stale/current_page=0. Unrelated callers retain metadata-based paging.
    private let rawPageSize: Int?
    private(set) var failedPage: Int?

    init(continuesWithoutPageCount: Bool = false, rawPageSize: Int? = nil, fetch: @escaping @Sendable (Int) async throws -> PageableResponse<Item>) {
        precondition(rawPageSize.map { $0 > 0 } ?? true, "rawPageSize must be positive")
        self.fetch = fetch
        self.continuesWithoutPageCount = continuesWithoutPageCount
        self.rawPageSize = rawPageSize
    }

    var isLoadingFirstPage: Bool { state == .loading && items.isEmpty }
    var isEmpty: Bool { items.isEmpty && state == .idle && !hasMore }

    var errorMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    /// Loads the first page, unless it is already loaded or loading.
    func loadFirstPageIfNeeded() async {
        guard !hasLoadedFirstPage, state == .idle else { return }
        await reload()
    }

    /// Loads page 0 again, keeping existing results until the refresh succeeds.
    /// Query changes create a new paginator instead of mixing two result sets.
    func reload() async {
        generation += 1
        let token = generation
        state = .loading
        failedPage = nil

        do {
            let page = try await fetch(0)
            try Task.checkCancellation()
            guard token == generation else { return }
            var seen = Set<Item.ID>()
            items = page.items.filter { seen.insert($0.id).inserted }
            totalCount = page.totalCount
            hasMore = canContinue(after: page)
            nextPage = 1
            hasLoadedFirstPage = true
            state = .idle
        } catch {
            guard token == generation else { return }
            if ProfileRequestFailure.isCancellation(error) { state = .idle; return }
            failedPage = 0
            state = .failed(Self.message(for: error))
        }
    }

    /// Loads the next page. Safe to call from `onAppear` of the last row.
    func loadNextPage() async {
        guard state == .idle, hasLoadedFirstPage else { return }
        await fetchNextPage()
    }

    /// Retry the failed page without discarding already displayed results.
    func retry() async {
        guard state != .loading else { return }
        if failedPage == 0 || !hasLoadedFirstPage { await reload() }
        else { await fetchNextPage() }
    }

    private func fetchNextPage() async {
        guard hasMore, state != .loading else { return }
        let token = generation
        let page = nextPage
        state = .loading
        failedPage = nil

        do {
            let response = try await fetch(page)
            try Task.checkCancellation()
            guard token == generation else { return }
            // The API can repeat an item across pages when the underlying list
            // changes mid-scroll; dropping duplicates keeps SwiftUI's diffing sane.
            var known = Set(items.map(\.id))
            items.append(contentsOf: response.items.filter { known.insert($0.id).inserted })
            totalCount = response.totalCount
            hasMore = canContinue(after: response)
            nextPage = page + 1
            state = .idle
        } catch {
            guard token == generation else { return }
            if ProfileRequestFailure.isCancellation(error) { state = .idle; return }
            failedPage = page
            state = .failed(Self.message(for: error))
        }
    }

    private func canContinue(after page: PageableResponse<Item>) -> Bool {
        // Count before deduplication, and never use cumulative total_count or the
        // response's stale current_page to choose the next requested index.
        if let rawPageSize { return page.items.count >= rawPageSize }
        if continuesWithoutPageCount, page.totalPageCount == nil { return !page.items.isEmpty }
        return !page.isLastPage
    }

    /// Replaces one item in place, for optimistic updates.
    func update(_ item: Item) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    func remove(id: Item.ID) {
        guard items.contains(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        if let totalCount { self.totalCount = max(0, totalCount - 1) }
    }

    /// Removing from a positional list shifts all later pages. Rebase from page
    /// zero and invalidate any load that started before the mutation completed.
    func removeAndReload(id: Item.ID) async {
        remove(id: id)
        await reload()
    }

    nonisolated static func message(for error: any Error) -> String {
        (error as? AnixartError)?.errorDescription ?? error.localizedDescription
    }
}
