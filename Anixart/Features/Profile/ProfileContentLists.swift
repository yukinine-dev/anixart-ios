import SwiftUI
import AnixartKit

@MainActor
struct ProfileCollectionsView: View {
    @Environment(AppEnvironment.self) private var env
    let profileID: Int
    @State private var viewer: ProfileViewerKey?
    @State private var paginator: Paginator<ReleaseCollection>?

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
                    NavigationLink { ProfileVideoDetailView(video: video, viewer: viewer) } label: { ProfileVideoRow(video: video) }
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
                if let playerURL {
                    Button { isPlaying = true } label: { Label("Воспроизвести", systemImage: "play.fill") }
                    ShareLink(item: playerURL) { Label("Поделиться", systemImage: "square.and.arrow.up") }
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
            }
        }
        .navigationTitle("Видео")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { if viewer == nil { viewer = env.session.viewerKey } }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { isPlaying = false }
        }
        .fullScreenCover(isPresented: $isPlaying) {
            if viewer == env.session.viewerKey, let playerURL { WebPlayerSheet(url: playerURL, title: video.title ?? "Видео") }
        }
    }
}
