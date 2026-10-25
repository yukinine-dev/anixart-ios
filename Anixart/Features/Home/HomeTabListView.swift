import SwiftUI
import AnixartKit

/// One preset tab's release list. Paginated against `filter/{page}`.
@MainActor
struct HomeTabListView: View {
    @Environment(AppEnvironment.self) private var env

    let tab: HomeTab
    var onOverflow: (Release) -> Void

    @State private var paginator: Paginator<Release>?
    @State private var opened: Release?

    var body: some View {
        List {
            if let paginator {
                PaginatedContent(
                    paginator: paginator,
                    emptyTitle: "Пока ничего нет",
                    emptyMessage: "В этой вкладке нет релизов"
                ) { release in
                    // A tap gesture rather than a NavigationLink wrapper: the row has
                    // its own overflow button, and a Button nested inside a link's
                    // label does not reliably get its taps.
                    ReleaseListRow(release: release) { onOverflow(release) }
                        .onTapGesture { opened = release }
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await paginator?.reload() }
        .navigationDestination(item: $opened) { release in
            ReleaseDetailView(releaseID: release.id, preloaded: release)
        }
        // Rebuilt when the tab changes, so each tab keeps its own filter and paging.
        .task(id: tab) {
            paginator = makePaginator()
            await paginator?.loadFirstPageIfNeeded()
        }
    }

    private func makePaginator() -> Paginator<Release> {
        let client = env.client
        let filter = tab.filter ?? FilterRequest()
        return Paginator { page in
            try await client.send(CatalogEndpoints.filter(filter, page: page))
        }
    }
}
