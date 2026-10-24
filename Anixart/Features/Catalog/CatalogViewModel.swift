import Foundation
import AnixartKit

/// Catalogue tab: browses `filter/{page}` and switches to `search/releases/{page}`
/// as soon as there is a query, which is how the Android app behaves.
@MainActor
@Observable
final class CatalogViewModel {
    /// Plain observable properties: the `@Observable` macro does not track a stored
    /// property that declares accessors, so reacting to changes goes through the
    /// methods below rather than `didSet`.
    var query = ""
    private(set) var filter = FilterRequest()

    private(set) var browse: Paginator<Release>
    private(set) var searchResults: [Release] = []
    private(set) var isSearching = false
    private(set) var searchError: String?
    private(set) var relatedSuggestion: Related?

    private let client: AnixartClient

    init(client: AnixartClient) {
        self.client = client
        self.browse = Self.makePaginator(client: client, filter: FilterRequest())
    }

    var isShowingSearch: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var activeFilterCount: Int {
        var count = 0
        if filter.categoryId != nil { count += 1 }
        if filter.statusId != nil { count += 1 }
        if filter.season != nil { count += 1 }
        if filter.startYear != nil || filter.endYear != nil { count += 1 }
        if filter.episodesFrom != nil { count += 1 }
        if !(filter.genres?.isEmpty ?? true) { count += 1 }
        if !(filter.types?.isEmpty ?? true) { count += 1 }
        if !(filter.ageRatings?.isEmpty ?? true) { count += 1 }
        if !(filter.profileListExclusions?.isEmpty ?? true) { count += 1 }
        return count
    }

    /// Applies a new filter and reloads the catalogue.
    func apply(filter newFilter: FilterRequest) {
        guard newFilter != filter else { return }
        filter = newFilter
        rebuildBrowse()
    }

    func resetFilter() {
        apply(filter: FilterRequest())
    }

    /// Debounced search, driven by the view with `.task(id: model.query)`.
    func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            searchResults = []
            relatedSuggestion = nil
            searchError = nil
            isSearching = false
            return
        }

        // Let a fast typist finish before spending a request.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        isSearching = true
        do {
            let response = try await client.send(CatalogEndpoints.searchReleases(text, page: 0))
            guard !Task.isCancelled else { return }
            applySearch(releases: response.releases ?? [], related: response.related, error: nil)
        } catch {
            guard !Task.isCancelled else { return }
            applySearch(releases: [], related: nil, error: Paginator<Release>.message(for: error))
        }
    }

    private static func makePaginator(client: AnixartClient, filter: FilterRequest) -> Paginator<Release> {
        Paginator { page in
            try await client.send(CatalogEndpoints.filter(filter, page: page))
        }
    }

    private func rebuildBrowse() {
        browse = Self.makePaginator(client: client, filter: filter)
        Task { await browse.reload() }
    }

    private func applySearch(releases: [Release], related: Related?, error: String?) {
        searchResults = releases
        relatedSuggestion = related
        searchError = error
        isSearching = false
    }
}
