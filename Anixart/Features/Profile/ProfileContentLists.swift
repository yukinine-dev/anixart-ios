import SwiftUI
import UIKit
import AnixartKit

@MainActor
struct ProfileCollectionsView: View {
    @Environment(AppEnvironment.self) private var env
    let profileID: Int
    @State private var viewer: ProfileViewerKey?
    @State private var paginator: Paginator<ReleaseCollection>?
    @State private var showsSearch = false

    init(profileID: Int, viewer: ProfileViewerKey? = nil) {
        self.profileID = profileID
        _viewer = State(initialValue: viewer)
    }

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Коллекций пока нет") { collection in
                    NavigationLink { CollectionDetailView(collection: collection, viewer: viewer) } label: { CollectionRow(collection: collection) }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Коллекции")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { showsSearch = true } label: { Image(systemName: "magnifyingglass") }
        } }
        .navigationDestination(isPresented: $showsSearch) { ProfileCollectionSearchView(viewer: viewer) }
        .refreshable { await paginator?.reload() }
        .task {
            if viewer == nil { viewer = env.session.viewerKey }
            guard let viewer, viewer == env.session.viewerKey else { return }
            if paginator == nil {
                let session = env.session
                let id = profileID
                paginator = Paginator { page in try await session.sendViewerRequest(ProfileEndpoints.collections(profileID: id, page: page), for: viewer) }
            }
            await paginator?.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { paginator = nil }
        }
    }
}

@MainActor
struct ProfileVideosView: View {
    @Environment(AppEnvironment.self) private var env
    let profileID: Int
    @State private var viewer: ProfileViewerKey?
    @State private var paginator: Paginator<ReleaseVideo>?

    init(profileID: Int, viewer: ProfileViewerKey? = nil) {
        self.profileID = profileID
        _viewer = State(initialValue: viewer)
    }

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Видео пока нет") { video in
                    ProfileVideoEntry(video: video, viewer: viewer)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Видео")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await paginator?.reload() }
        .task {
            if viewer == nil { viewer = env.session.viewerKey }
            guard let viewer, viewer == env.session.viewerKey else { return }
            if paginator == nil {
                let session = env.session
                let id = profileID
                paginator = Paginator { page in try await session.sendViewerRequest(ProfileEndpoints.videos(profileID: id, page: page), for: viewer) }
            }
            await paginator?.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { paginator = nil }
        }
    }
}

@MainActor
struct ProfileVideoRow: View {
    let video: ReleaseVideo
    var body: some View {
        HStack(spacing: 16) {
            CachedAsyncImage(url: AnixartURL.image(video.image), maxPixelSize: 360) { $0.resizable().scaledToFill() } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 112, height: 63)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay { Image(systemName: "play.fill").foregroundStyle(.white).shadow(radius: 3) }
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title ?? "Видео").font(.ax(.subheadline)).foregroundStyle(.primary).lineLimit(2)
                if let author = video.profile { Text(author.displayLogin).font(.ax(.caption)).foregroundStyle(.secondary) }
                if let release = video.release?.value { Text(release.displayTitle).font(.ax(.caption)).foregroundStyle(.secondary).lineLimit(1) }
                if let category = video.category?.name { Text(category).font(.ax(.caption)).foregroundStyle(.secondary) }
                if let timestamp = video.timestamp { Text(ProfileDate.text(timestamp)).font(.ax(.caption)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
    }
}

@MainActor
struct ProfileVideoDetailView: View {
    @Environment(AppEnvironment.self) private var env
    let video: ReleaseVideo
    @State private var viewer: ProfileViewerKey?
    @State private var isPlaying = false
    @State private var favorite: Bool?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(video: ReleaseVideo, viewer: ProfileViewerKey? = nil) {
        self.video = video
        _viewer = State(initialValue: viewer)
    }

    private var playerURL: URL? {
        for value in [video.playerUrl, video.url] {
            if let url = ProfileWebURL.url(value) { return url }
        }
        return nil
    }

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey {
            Section {
                CachedAsyncImage(url: AnixartURL.image(video.image), maxPixelSize: 1200) { $0.resizable().scaledToFit() } placeholder: {
                    Rectangle().fill(.quaternary).aspectRatio(16 / 9, contentMode: .fit)
                }
                Text(video.title ?? "Видео").font(.ax(.title3, .medium))
                LabeledContent("Источник", value: "Anixart")
                if let timestamp = video.timestamp { LabeledContent("Дата", value: ProfileDate.dateTime(timestamp)) }
                if let category = video.category?.name { LabeledContent("Категория", value: category) }
                if let playerURL {
                    Button { isPlaying = true } label: { Label("Воспроизвести", systemImage: "play.fill") }
                    ShareLink(item: playerURL) { Label("Поделиться", systemImage: "square.and.arrow.up") }
                    ShareLink(item: playerURL) { Label("Открыть в…", systemImage: "arrow.up.forward.app") }
                    Button { UIPasteboard.general.url = playerURL } label: { Label("Скопировать ссылку", systemImage: "link") }
                } else { Text("Ссылка на видео недоступна").foregroundStyle(.secondary) }
            }
            if let author = video.profile {
                Section("Добавил") {
                    NavigationLink { ProfileView(profileID: author.id, viewer: viewer) } label: {
                        HStack { Avatar(url: author.avatarURL, size: 40); Text(author.displayLogin) }
                    }
                }
            }
            if let releaseID = video.release?.id {
                Section {
                    NavigationLink { ReleaseDetailView(releaseID: releaseID, preloaded: video.release?.value, viewer: viewer) } label: {
                        Text(video.release?.value?.displayTitle ?? "Открыть релиз")
                    }
                }
            }
            if viewer?.account != nil {
                Section {
                    Button { Task { await toggleFavorite() } } label: {
                        Label((favorite ?? video.isFavorite) == true ? "Убрать у себя" : "Добавить к себе", systemImage: "bookmark")
                    }.disabled(isSaving)
                }
            }
            ProfileSaveError(message: errorMessage)
            }
        }
        .navigationTitle("Видео")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { if viewer == nil { viewer = env.session.viewerKey } }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { isPlaying = false; favorite = nil; errorMessage = nil }
        }
        .fullScreenCover(isPresented: $isPlaying) {
            if viewer == env.session.viewerKey, let playerURL { WebPlayerSheet(url: playerURL, title: video.title ?? "Видео") }
        }
    }

    private func toggleFavorite() async {
        guard !isSaving, let viewer, viewer == env.session.viewerKey, let account = viewer.account else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let wasFavorite = (favorite ?? video.isFavorite) == true
        do {
            try await env.session.sendConfirmedAccountRequest(wasFavorite
                ? ReleaseVideoEndpoints.removeFavorite(videoID: video.id)
                : ReleaseVideoEndpoints.addFavorite(videoID: video.id), for: account)
            favorite = !wasFavorite
            await env.session.refreshProfile(for: account)
        } catch { if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) } }
    }
}

@MainActor
struct ProfileVideoEntry: View {
    @Environment(AppEnvironment.self) private var env
    let video: ReleaseVideo
    let viewer: ProfileViewerKey?
    @State private var playsVideo = false
    @State private var showsInfo = false
    @State private var showsMissingURL = false

    private var playerURL: URL? { ProfileWebURL.url(video.playerUrl) ?? ProfileWebURL.url(video.url) }

    var body: some View {
        HStack {
            Button {
                if playerURL != nil { playsVideo = true } else { showsMissingURL = true }
            } label: { ProfileVideoRow(video: video) }
            .buttonStyle(.plain).disabled(viewer != env.session.viewerKey)
            Button { showsInfo = true } label: { Image(systemName: "ellipsis").padding(10) }
                .buttonStyle(.borderless).accessibilityLabel("Информация о видео")
        }
        .contextMenu { Button("Информация о видео") { showsInfo = true } }
        .fullScreenCover(isPresented: $playsVideo) {
            if viewer == env.session.viewerKey, let playerURL { WebPlayerSheet(url: playerURL, title: video.title ?? "Видео") }
        }
        .sheet(isPresented: $showsInfo) {
            NavigationStack {
                ProfileVideoDetailView(video: video, viewer: viewer)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { showsInfo = false } } }
            }
        }
        .alert("Видео недоступно", isPresented: $showsMissingURL) { Button("Понятно", role: .cancel) { } } message: {
            Text("Сервер не вернул ссылку для воспроизведения.")
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { playsVideo = false; showsInfo = false }
        }
    }
}

@MainActor
struct ProfileCollectionSearchView: View {
    @Environment(AppEnvironment.self) private var env
    let viewer: ProfileViewerKey?
    @State private var query = ""
    @State private var paginator: Paginator<ReleaseCollection>?

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Ничего не найдено") { collection in
                    NavigationLink { CollectionDetailView(collection: collection, viewer: viewer) } label: { CollectionRow(collection: collection) }
                }
            }
        }
        .listStyle(.plain).navigationTitle("Поиск коллекций").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Поиск коллекций")
        .task(id: query) {
            paginator = nil
            guard let viewer, viewer == env.session.viewerKey else { return }
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            let session = env.session
            let list = Paginator<ReleaseCollection> { page in
                // Deliberately global: no owner filter is added to this endpoint.
                try await session.sendViewerRequest(CatalogEndpoints.searchCollections(query, page: page), for: viewer)
            }
            paginator = list
            await list.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in if viewer != current { paginator = nil } }
    }
}
