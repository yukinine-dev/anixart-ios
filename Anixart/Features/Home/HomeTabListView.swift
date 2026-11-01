import SwiftUI
import AnixartKit

/// One preset tab's release list. Paginated against `filter/{page}`.
@MainActor
struct HomeTabListView: View {
    @Environment(AppEnvironment.self) private var env

    let tab: HomeTab

    @State private var model: ReleaseFeedModel?
    @State private var opened: Release?
    @State private var listTarget: Release?

    private var feedKey: ReleaseFeedKey {
        ReleaseFeedKey(filter: tab.filter ?? FilterRequest(), viewer: env.session.viewerKey)
    }

    var body: some View {
        List {
            if let model, model.hasCurrentViewer, model.filter == feedKey.filter {
                PaginatedContent(
                    paginator: model.paginator,
                    emptyTitle: "Пока ничего нет",
                    emptyMessage: "В этой вкладке нет релизов"
                ) { release in
                    // A tap gesture rather than a NavigationLink wrapper: the row has
                    // its own overflow button, and a Button nested inside a link's
                    // label does not reliably get its taps.
                    ReleaseListRow(release: release) { listTarget = release }
                        .onTapGesture { opened = release }
                        // The row draws its own card, so the list must not draw a
                        // background or a separator behind it.
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await model?.paginator.reload() }
        .sheet(item: $listTarget) { release in
            if let model { ReleaseQuickActionsSheet(release: release, viewer: model.viewer, feed: model) }
        }
        .navigationDestination(item: $opened) { release in
            ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: model?.viewer)
        }
        .task(id: feedKey) {
            if model?.viewer != feedKey.viewer || model?.filter != feedKey.filter {
                model = ReleaseFeedModel(filter: feedKey.filter, session: env.session)
                opened = nil
                listTarget = nil
            }
            let current = model
            await current?.paginator.loadFirstPageIfNeeded()
        }
    }
}
