import SwiftUI
import AnixartKit

/// Collections the user bookmarked (`collectionFavorite/all/{page}`).
@MainActor
struct FavoriteCollectionsList: View {
    @Environment(AppEnvironment.self) private var env
    @State private var paginator: Paginator<ReleaseCollection>?

    var body: some View {
        List {
            if let paginator {
                PaginatedContent(
                    paginator: paginator,
                    emptyTitle: "Нет сохранённых коллекций",
                    emptyMessage: "Добавляйте коллекции в закладки с их страницы"
                ) { collection in
                    NavigationLink {
                        CollectionDetailView(collection: collection)
                    } label: {
                        CollectionRow(collection: collection)
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await paginator?.reload() }
        .task {
            if paginator == nil {
                let client = env.client
                paginator = Paginator { page in
                    try await client.send(CollectionEndpoints.favorites(page: page))
                }
            }
            await paginator?.loadFirstPageIfNeeded()
        }
    }
}

@MainActor
struct CollectionRow: View {
    let collection: ReleaseCollection

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.row) {
            AsyncImage(url: collection.coverURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 96, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(collection.displayTitle)
                    .font(.ax(.subheadline, .medium))
                    .lineLimit(2)
                if let creator = collection.creator?.login {
                    Text(creator).font(.ax(.caption)).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Label(Format.count(collection.favoriteCount), systemImage: "bookmark")
                        .labelStyle(.compact)
                    Label(Format.count(collection.commentCount), systemImage: "bubble.left")
                        .labelStyle(.compact)
                    if collection.isPrivate == true {
                        Label("Приватная", systemImage: "lock").labelStyle(.compact)
                    }
                }
                .font(.ax(.caption2))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

@MainActor
struct CollectionDetailView: View {
    @Environment(AppEnvironment.self) private var env

    let collection: ReleaseCollection
    @State private var paginator: Paginator<Release>?
    @State private var isFavorite: Bool?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if let description = collection.description, !description.isEmpty {
                        Text(description).font(.ax(.subheadline))
                    }
                    Button {
                        Task { await toggleFavorite() }
                    } label: {
                        Label(
                            favoriteState ? "В закладках" : "В закладки",
                            systemImage: favoriteState ? "bookmark.fill" : "bookmark"
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
                }
            }

            Section("Релизы") {
                if let paginator {
                    PaginatedContent(paginator: paginator, emptyTitle: "В коллекции пока нет релизов") { release in
                        NavigationLink {
                            ReleaseDetailView(releaseID: release.id, preloaded: release)
                        } label: {
                            ReleaseRow(release: release)
                        }
                    }
                }
            }
        }
        .navigationTitle(collection.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if paginator == nil {
                let client = env.client
                let id = collection.id
                paginator = Paginator { page in
                    try await client.send(CollectionEndpoints.releases(collectionID: id, page: page))
                }
            }
            await paginator?.loadFirstPageIfNeeded()
        }
    }

    private var favoriteState: Bool {
        isFavorite ?? (collection.isFavorite ?? false)
    }

    private func toggleFavorite() async {
        guard env.session.isSignedIn else {
            env.session.promptSignIn()
            return
        }
        let wasFavorite = favoriteState
        isFavorite = !wasFavorite
        do {
            if wasFavorite {
                try await env.client.send(CollectionEndpoints.removeFavorite(collectionID: collection.id))
            } else {
                try await env.client.send(CollectionEndpoints.addFavorite(collectionID: collection.id))
            }
        } catch {
            isFavorite = wasFavorite
        }
    }
}
