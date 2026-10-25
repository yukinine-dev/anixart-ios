import SwiftUI
import AnixartKit

/// The ⓘ next to the title: all three titles the release carries.
@MainActor
struct ReleaseTitlesView: View {
    let release: Release

    var body: some View {
        List {
            if let ru = release.titleRu, !ru.isEmpty {
                field("Название", ru)
            }
            if let original = release.titleOriginal, !original.isEmpty {
                field("Оригинальное название", original)
            }
            if let alt = release.titleAlt, !alt.isEmpty {
                field("Альтернативные названия", alt)
            }
        }
        .navigationTitle("Названия")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.ax(.caption)).foregroundStyle(.secondary)
            Text(value).font(.ax(.subheadline)).textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

/// Public collections that contain this release.
@MainActor
struct ReleaseCollectionsView: View {
    @Environment(AppEnvironment.self) private var env

    let releaseID: Int
    let title: String
    @State private var paginator: Paginator<ReleaseCollection>?

    var body: some View {
        List {
            if let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Релиза пока нет ни в одной коллекции") { collection in
                    NavigationLink {
                        CollectionDetailView(collection: collection)
                    } label: {
                        HStack(spacing: Theme.Spacing.row) {
                            AsyncImage(url: collection.coverURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle().fill(.quaternary)
                            }
                            .frame(width: 72, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(collection.displayTitle).font(.ax(.headline)).lineLimit(2)
                                if let creator = collection.creator?.login {
                                    Text(creator).font(.ax(.caption)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("В коллекциях")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if paginator == nil {
                let client = env.client
                let id = releaseID
                paginator = Paginator { page in
                    try await client.send(CollectionEndpoints.containing(releaseID: id, page: page))
                }
            }
            await paginator?.loadFirstPageIfNeeded()
        }
    }
}

/// "Добавить к себе в коллекцию": pick one of your own collections.
@MainActor
struct AddToCollectionSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let releaseID: Int
    @State private var collections: [ReleaseCollection] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if !env.session.isSignedIn {
                    SignInPromptView(message: "Войдите, чтобы собирать коллекции.")
                } else if isLoading {
                    ProgressView()
                } else if collections.isEmpty {
                    StatusMessageView(
                        title: "Коллекций пока нет",
                        message: "Создайте коллекцию в приложении Anixart, и она появится здесь",
                        systemImage: "square.on.square"
                    )
                } else {
                    List(collections) { collection in
                        Button {
                            dismiss()
                        } label: {
                            Text(collection.displayTitle)
                        }
                    }
                }
            }
            .navigationTitle("Моя коллекция")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        guard let profileID = env.session.currentProfileID, collections.isEmpty else { return }
        isLoading = true
        if let page = try? await env.client.send(CollectionEndpoints.byProfile(profileID, page: 0)) {
            collections = page.content ?? []
        }
        isLoading = false
    }
}

/// Trailers and previews, behind "Видео → Показать все".
@MainActor
struct ReleaseVideosView: View {
    @Environment(AppEnvironment.self) private var env

    let release: Release
    var category: String?

    @State private var paginator: Paginator<ReleaseVideo>?
    @State private var playing: ReleaseVideo?

    var body: some View {
        List {
            if let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Видео пока нет") { video in
                    Button {
                        playing = video
                    } label: {
                        HStack(spacing: Theme.Spacing.row) {
                            AsyncImage(url: AnixartURL.image(video.image)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle().fill(.quaternary)
                            }
                            .frame(width: 112, height: 63)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                Image(systemName: "play.fill").foregroundStyle(.white.opacity(0.9))
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(video.title ?? "Видео")
                                    .font(.ax(.subheadline))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                if let category = video.category?.name {
                                    Text(category).font(.ax(.caption)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(category ?? "Видео")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playing) { video in
            if let url = (video.playerUrl ?? video.url).flatMap(URL.init(string:)) {
                WebPlayerSheet(url: url, title: video.title ?? "Видео")
            }
        }
        .task {
            if paginator == nil {
                let client = env.client
                let id = release.id
                paginator = Paginator { page in
                    try await client.send(ReleaseVideoEndpoints.videos(releaseID: id, page: page))
                }
            }
            await paginator?.loadFirstPageIfNeeded()
        }
    }
}

/// "Онлайн просмотр": the official streaming services Anixart knows about.
@MainActor
struct StreamingPlatformsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL

    let release: Release

    @State private var platforms: [ReleaseStreamingPlatform]?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.row) {
                Text("Результаты поиска")
                    .font(.ax(.title3))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, Theme.Spacing.row)

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if let platforms, !platforms.isEmpty {
                    ForEach(platforms) { platform in
                        Button {
                            if let url = platform.url.flatMap(URL.init(string:)) { openURL(url) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(platform.name ?? "Сервис")
                                        .font(.ax(.title3, .medium))
                                        .foregroundStyle(.primary)
                                    Text("Официальный сервис")
                                        .font(.ax(.subheadline))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding(16)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("К сожалению, не удалось найти официальные проверенные стриминговые сервисы")
                        .font(.ax(.title3))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal)
                }
            }
        }
        .navigationTitle("Онлайн просмотр")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard platforms == nil else { return }
        isLoading = true
        if let page = try? await env.client.send(ReleaseEndpoints.streamingPlatforms(releaseID: release.id)) {
            platforms = page.content ?? []
        } else {
            platforms = []
        }
        isLoading = false
    }
}

/// Full-screen web view for a trailer, which is always a hosting's player page.
@MainActor
struct WebPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let url: URL
    let title: String

    var body: some View {
        EmbedPlayerView(url: url, title: title)
            .ignoresSafeArea()
            .background(.black)
            .overlay(alignment: .topLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.ax(.headline))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .padding()
            }
    }
}

/// Releases carrying one genre, reached by tapping a genre on the release page.
@MainActor
struct GenreReleasesView: View {
    @Environment(AppEnvironment.self) private var env

    let genres: [String]
    @State private var paginator: Paginator<Release>?

    var body: some View {
        List {
            if let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Ничего не нашлось") { release in
                    NavigationLink {
                        ReleaseDetailView(releaseID: release.id, preloaded: release)
                    } label: {
                        ReleaseRow(release: release)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(genres.joined(separator: ", ").capitalizedFirst)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if paginator == nil {
                let client = env.client
                let request = FilterRequest(genres: genres)
                paginator = Paginator { page in
                    try await client.send(CatalogEndpoints.filter(request, page: page))
                }
            }
            await paginator?.loadFirstPageIfNeeded()
        }
    }
}
