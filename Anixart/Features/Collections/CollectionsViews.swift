import SwiftUI
import UIKit
import AnixartKit

/// Collections the user bookmarked (`collectionFavorite/all/{page}`).
@MainActor
struct FavoriteCollectionsList: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewer: ProfileViewerKey?
    @State private var paginator: Paginator<ReleaseCollection>?

    var body: some View {
        List {
            if viewer == env.session.viewerKey, let paginator {
                PaginatedContent(
                    paginator: paginator,
                    emptyTitle: "Нет сохранённых коллекций",
                    emptyMessage: "Добавляйте коллекции в закладки с их страницы"
                ) { collection in
                    NavigationLink {
                        CollectionDetailView(collection: collection, viewer: viewer)
                    } label: {
                        CollectionRow(collection: collection)
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await paginator?.reload() }
        .task(id: env.session.viewerKey) {
            let viewer = env.session.viewerKey
            self.viewer = viewer
            let session = env.session
            let list = Paginator<ReleaseCollection> { page in
                try await session.sendViewerRequest(CollectionEndpoints.favorites(page: page), for: viewer)
            }
            paginator = list
            await list.loadFirstPageIfNeeded()
        }
    }
}

@MainActor
struct CollectionRow: View {
    let collection: ReleaseCollection

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.row) {
            CachedAsyncImage(url: collection.coverURL, maxPixelSize: 160) { image in
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
    @State private var viewer: ProfileViewerKey?
    @State private var paginator: Paginator<Release>?
    @State private var isFavorite: Bool?
    @State private var isSavingFavorite = false
    @State private var favoriteError: String?
    @State private var report: ProfileReportPresentation?

    init(collection: ReleaseCollection, viewer: ProfileViewerKey? = nil) {
        self.collection = collection
        _viewer = State(initialValue: viewer)
    }

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey {
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
                    .disabled(isSavingFavorite)
                }
            }

            Section {
                if let creator = collection.creator {
                    NavigationLink { ProfileView(profileID: creator.id, viewer: viewer) } label: {
                        HStack(spacing: 12) {
                            Avatar(url: AnixartURL.image(creator.avatar), size: 36)
                            Text(creator.login ?? "Автор коллекции")
                        }
                    }
                }
                NavigationLink {
                    ProfileCommentsAtLocationView(location: ProfileCommentLocation(category: .collections, parentID: collection.id), viewer: viewer)
                } label: { Label("Комментарии · \(Format.count(collection.commentCount))", systemImage: "bubble.left") }
            }

            Section("Релизы") {
                if let paginator {
                    PaginatedContent(paginator: paginator, emptyTitle: "В коллекции пока нет релизов") { release in
                        NavigationLink {
                            ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: viewer)
                        } label: {
                            ReleaseRow(release: release)
                        }
                    }
                }
            }
            }
        }
        .navigationTitle(viewer == env.session.viewerKey ? collection.displayTitle : "Коллекция")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ShareLink(item: AnixartEnvironment.webBaseURL.appendingPathComponent("collection/\(collection.id)")) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }
                Button { UIPasteboard.general.url = AnixartEnvironment.webBaseURL.appendingPathComponent("collection/\(collection.id)") } label: {
                    Label("Скопировать ссылку", systemImage: "link")
                }
                if let account = viewer?.account {
                    Button {
                        report = ProfileReportPresentation(kind: .collection, entityID: collection.id,
                                                           title: collection.displayTitle, account: account)
                    } label: { Label("Пожаловаться", systemImage: "flag") }
                }
            } label: { Image(systemName: "ellipsis") }
            .disabled(viewer != env.session.viewerKey)
        } }
        .sheet(item: $report) { ProfileReportView(target: $0) }
        .refreshable { await paginator?.reload() }
        .task {
            if viewer == nil { viewer = env.session.viewerKey }
            guard let viewer, viewer == env.session.viewerKey else { return }
            if paginator == nil {
                paginator = BrowsingPaginators.collectionReleases(collectionID: collection.id, viewer: viewer, session: env.session)
            }
            await paginator?.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            guard viewer != current else { return }
            paginator = nil
            isFavorite = nil
            favoriteError = nil
            report = nil
        }
        .alert("Не удалось изменить закладки", isPresented: Binding(
            get: { favoriteError != nil }, set: { if !$0 { favoriteError = nil } }
        )) {
            Button("Понятно", role: .cancel) { favoriteError = nil }
        } message: {
            Text(favoriteError ?? "")
        }
    }

    private var favoriteState: Bool {
        isFavorite ?? (collection.isFavorite ?? false)
    }

    private func toggleFavorite() async {
        guard !isSavingFavorite, let viewer, viewer == env.session.viewerKey else { return }
        guard let account = viewer.account else {
            env.session.promptSignIn()
            return
        }
        let wasFavorite = favoriteState
        isSavingFavorite = true
        favoriteError = nil
        defer { isSavingFavorite = false }
        isFavorite = !wasFavorite
        do {
            if wasFavorite {
                try await env.session.sendConfirmedAccountRequest(CollectionEndpoints.removeFavorite(collectionID: collection.id), for: account)
            } else {
                try await env.session.sendConfirmedAccountRequest(CollectionEndpoints.addFavorite(collectionID: collection.id), for: account)
            }
        } catch {
            guard viewer == env.session.viewerKey else { return }
            isFavorite = wasFavorite
            if !ProfileRequestFailure.isCancellation(error) { favoriteError = Paginator<Release>.message(for: error) }
        }
    }
}
