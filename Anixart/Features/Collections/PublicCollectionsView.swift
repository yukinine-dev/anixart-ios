import SwiftUI
import AnixartKit

/// Public collection browsing is separate from the user's bookmarked collections.
@MainActor
struct PublicCollectionsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewer: ProfileViewerKey?
    @State private var paginator: Paginator<ReleaseCollection>?

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Коллекций пока нет") { collection in
                    NavigationLink { CollectionDetailView(collection: collection, viewer: viewer) } label: {
                        CollectionRow(collection: collection)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Коллекции")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await paginator?.reload() }
        .task {
            if viewer == nil { viewer = env.session.viewerKey }
            guard let viewer, viewer == env.session.viewerKey else { return }
            if paginator == nil {
                paginator = BrowsingPaginators.publicCollections(viewer: viewer, session: env.session)
            }
            await paginator?.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in if viewer != current { paginator = nil } }
    }
}
