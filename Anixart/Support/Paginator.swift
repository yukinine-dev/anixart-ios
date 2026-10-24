import Foundation
import AnixartKit

/// Drives one infinitely-scrolling list.
///
/// Anixart pages are zero-based and report `total_page_count`, so the paginator
/// knows when it has reached the end instead of probing for an empty page. It also
/// guards against the two bugs these lists usually have: a second load firing while
/// the first is in flight, and a stale response from a previous query overwriting
/// newer results.
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

    init(fetch: @escaping @Sendable (Int) async throws -> PageableResponse<Item>) {
        self.fetch = fetch
    }

    var isLoadingFirstPage: Bool { state == .loading && items.isEmpty }
    var isEmpty: Bool { items.isEmpty && state == .idle && !hasMore }

    var errorMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    /// Loads the first page, unless it is already loaded or loading.
    func loadFirstPageIfNeeded() async {
        guard items.isEmpty, state != .loading else { return }
        await reload()
    }

    /// Discards everything and loads page 0 again. Used by pull-to-refresh and
    /// whenever the query behind the list changes.
    func reload() async {
        generation += 1
        let token = generation
        nextPage = 0
        hasMore = true
        state = .loading

        do {
            let page = try await fetch(0)
            guard token == generation else { return }
            items = page.items
            totalCount = page.totalCount
            hasMore = !page.isLastPage
            nextPage = 1
            state = .idle
        } catch {
            guard token == generation else { return }
            items = []
            hasMore = false
            state = .failed(Self.message(for: error))
        }
    }

    /// Loads the next page. Safe to call from `onAppear` of the last row.
    func loadNextPage() async {
        guard hasMore, state != .loading else { return }
        let token = generation
        let page = nextPage
        state = .loading

        do {
            let response = try await fetch(page)
            guard token == generation else { return }
            // The API can repeat an item across pages when the underlying list
            // changes mid-scroll; dropping duplicates keeps SwiftUI's diffing sane.
            let known = Set(items.map(\.id))
            items.append(contentsOf: response.items.filter { !known.contains($0.id) })
            totalCount = response.totalCount
            hasMore = !response.isLastPage
            nextPage = page + 1
            state = .idle
        } catch {
            guard token == generation else { return }
            hasMore = false
            state = .failed(Self.message(for: error))
        }
    }

    /// Replaces one item in place, for optimistic updates.
    func update(_ item: Item) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    func remove(id: Item.ID) {
        items.removeAll { $0.id == id }
        if let totalCount { self.totalCount = max(0, totalCount - 1) }
    }

    nonisolated static func message(for error: any Error) -> String {
        (error as? AnixartError)?.errorDescription ?? error.localizedDescription
    }
}
