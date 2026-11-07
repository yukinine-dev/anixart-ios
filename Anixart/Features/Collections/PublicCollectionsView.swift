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
            Section {
                NavigationLink {
                    FavoriteCollectionsList()
                } label: {
                    Label("Мои коллекции", systemImage: "bookmark.fill")
                        .font(.ax(.subheadline, .medium))
                }
            }
            if viewer == env.session.viewerKey, let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Коллекций пока нет") { collection in
                    NavigationLink { CollectionDetailView(collection: collection, viewer: viewer) } label: {
                        PublicCollectionCard(collection: collection)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
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

/// Android presents public collections as wide visual cards with the cover and
/// counters visible at a glance, not as compact two-line rows.
@MainActor
private struct PublicCollectionCard: View {
    let collection: ReleaseCollection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                CachedAsyncImage(url: collection.coverURL, maxPixelSize: 900) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 172)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.82)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                Text(collection.displayTitle)
                    .font(.ax(.headline, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 14) {
                if let creator = collection.creator?.login, !creator.isEmpty {
                    Label(creator, systemImage: "person")
                        .lineLimit(1)
                }
                Label(Format.count(collection.commentCount), systemImage: "bubble.left")
                Label(Format.count(collection.favoriteCount), systemImage: "bookmark")
                Spacer(minLength: 0)
            }
            .font(.ax(.caption))
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}