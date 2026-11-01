import SwiftUI
import UIKit
import AnixartKit

/// The ⓘ next to the title: all three titles the release carries.
@MainActor
struct ReleaseTitlesView: View {
    @Environment(\.dismiss) private var dismiss
    let release: Release

    var body: some View {
        NavigationStack {
            List {
                ForEach(release.titleFields) { field in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.label).font(.ax(.caption)).foregroundStyle(.secondary)
                            Text(field.value).font(.ax(.subheadline)).textSelection(.enabled)
                        }
                        Spacer(minLength: 0)
                        Button { UIPasteboard.general.string = field.value } label: {
                            Image(systemName: "doc.on.doc").font(.ax(.body))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Скопировать: \(field.label)")
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Названия")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Public collections that contain this release.
@MainActor
struct ReleaseCollectionsView: View {
    @Environment(AppEnvironment.self) private var env

    let releaseID: Int
    let title: String
    @State private var viewer: ProfileViewerKey?
    @State private var paginator: Paginator<ReleaseCollection>?

    init(releaseID: Int, title: String, viewer: ProfileViewerKey? = nil) {
        self.releaseID = releaseID
        self.title = title
        _viewer = State(initialValue: viewer)
    }

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Релиза пока нет ни в одной коллекции") { collection in
                    NavigationLink {
                        CollectionDetailView(collection: collection, viewer: viewer)
                    } label: {
                        HStack(spacing: Theme.Spacing.row) {
                            CachedAsyncImage(url: collection.coverURL, maxPixelSize: 120) { image in
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
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await paginator?.reload() }
        .task {
            if viewer == nil { viewer = env.session.viewerKey }
            guard let viewer, viewer == env.session.viewerKey else { return }
            if paginator == nil {
                paginator = BrowsingPaginators.releaseCollections(releaseID: releaseID, viewer: viewer, session: env.session)
            }
            await paginator?.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { paginator = nil }
        }
    }
}

/// "Добавить к себе в коллекцию": pick one of your own collections.
@MainActor
struct AddToCollectionSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let releaseID: Int
    @State private var viewer: ProfileViewerKey?
    @State private var model: AddToCollectionViewModel?

    init(releaseID: Int, viewer: ProfileViewerKey? = nil) {
        self.releaseID = releaseID
        _viewer = State(initialValue: viewer)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewer, viewer != env.session.viewerKey {
                    ProfileViewerNotice(viewer: viewer)
                } else if let model {
                    if !model.isSignedIn {
                        SignInPromptView(message: "Войдите, чтобы собирать коллекции.")
                    } else {
                        List {
                            if let paginator = model.paginator {
                                PaginatedContent(paginator: paginator, emptyTitle: "Коллекций пока нет",
                                                 emptyMessage: "Создайте коллекцию в приложении Anixart, и она появится здесь") { collection in
                                    Button {
                                        Task { if await model.add(to: collection) { dismiss() } }
                                    } label: {
                                        HStack {
                                            Text(collection.displayTitle)
                                            Spacer()
                                            if model.addingCollectionID == collection.id { ProgressView() }
                                        }
                                    }
                                    .disabled(model.isAdding)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .refreshable { if !model.isAdding { await model.paginator?.reload() } }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Моя коллекция")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .task {
                if viewer == nil { viewer = env.session.viewerKey }
                guard let viewer, viewer == env.session.viewerKey else { return }
                if model == nil { model = AddToCollectionViewModel(releaseID: releaseID, viewer: viewer, session: env.session) }
                await model?.paginator?.loadFirstPageIfNeeded()
            }
            .onChange(of: env.session.viewerKey) { _, current in
                if viewer != current { model?.invalidate() }
            }
            .alert("Не удалось добавить релиз", isPresented: Binding(
                get: { model?.errorMessage != nil }, set: { if !$0 { model?.dismissError() } }
            )) {
                Button("Понятно", role: .cancel) { model?.dismissError() }
            } message: {
                Text(model?.errorMessage ?? "")
            }
        }
    }
}

/// Trailers and previews, behind "Видео → Показать все".
@MainActor
struct ReleaseVideosView: View {
    @Environment(AppEnvironment.self) private var env

    let release: Release
    let categoryID: Int?
    let categoryTitle: String?

    @State private var viewer: ProfileViewerKey?
    @State private var model: ReleaseVideosViewModel?
    @State private var playing: ReleaseVideo?

    init(release: Release, categoryID: Int? = nil, categoryTitle: String? = nil, viewer: ProfileViewerKey? = nil) {
        self.release = release
        self.categoryID = categoryID
        self.categoryTitle = categoryTitle
        _viewer = State(initialValue: viewer)
    }

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let model {
                PaginatedContent(paginator: model.paginator, emptyTitle: "Видео пока нет") { video in
                    Button {
                        playing = video
                    } label: {
                        HStack(spacing: Theme.Spacing.row) {
                            CachedAsyncImage(url: AnixartURL.image(video.image), maxPixelSize: 240) { image in
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
                    .disabled(video.playbackURL == nil)
                    .accessibilityHint(video.playbackURL == nil ? "Ссылка на видео недоступна" : "")
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(categoryTitle ?? "Видео")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await model?.paginator.reload() }
        .fullScreenCover(item: $playing) { video in
            if viewer == env.session.viewerKey, let url = video.playbackURL {
                WebPlayerSheet(url: url, title: video.title ?? "Видео")
            }
        }
        .task {
            if viewer == nil { viewer = env.session.viewerKey }
            guard let viewer, viewer == env.session.viewerKey else { return }
            if model == nil {
                model = ReleaseVideosViewModel(releaseID: release.id, categoryID: categoryID, viewer: viewer, session: env.session)
            }
            await model?.paginator.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { model = nil; playing = nil }
        }
    }
}

/// "Онлайн просмотр": the official streaming services Anixart knows about.
@MainActor
struct StreamingPlatformsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL

    let release: Release

    @State private var viewer: ProfileViewerKey?
    @State private var resource = ProfileResource<PageableResponse<ReleaseStreamingPlatform>>()

    init(release: Release, viewer: ProfileViewerKey? = nil) {
        self.release = release
        _viewer = State(initialValue: viewer)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.row) {
                ProfileViewerNotice(viewer: viewer)
                if viewer == env.session.viewerKey {
                    Text("Результаты поиска")
                        .font(.ax(.title3))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, Theme.Spacing.row)

                    if resource.value == nil {
                        ProfileResourceState(resource: resource, title: "Не удалось загрузить сервисы", retry: load)
                    } else if let page = resource.value, !page.items.isEmpty {
                        ForEach(page.items) { platform in
                            Button {
                                if let url = platform.destinationURL { openURL(url) }
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
                            .disabled(platform.destinationURL == nil)
                            .accessibilityHint(platform.destinationURL == nil ? "Ссылка на сервис недоступна" : "")
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
        }
        .navigationTitle("Онлайн просмотр")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            if viewer == nil { viewer = env.session.viewerKey }
            await load()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { resource.reset() }
        }
    }

    private func load() async {
        guard let viewer, viewer == env.session.viewerKey else { return }
        await resource.load { try await env.session.sendViewerRequest(ReleaseEndpoints.streamingPlatforms(releaseID: release.id), for: viewer) }
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
    @State private var viewer: ProfileViewerKey?
    @State private var paginator: Paginator<Release>?

    init(genres: [String], viewer: ProfileViewerKey? = nil) {
        self.genres = genres
        _viewer = State(initialValue: viewer)
    }

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Ничего не нашлось") { release in
                    NavigationLink {
                        ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: viewer)
                    } label: {
                        ReleaseRow(release: release)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(genres.joined(separator: ", ").capitalizedFirst)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await paginator?.reload() }
        .task {
            if viewer == nil { viewer = env.session.viewerKey }
            guard let viewer, viewer == env.session.viewerKey else { return }
            if paginator == nil {
                let session = env.session
                let request = FilterRequest(genres: genres)
                paginator = Paginator(rawPageSize: 25) { page in
                    try await session.sendViewerRequest(CatalogEndpoints.filter(request, page: page), for: viewer)
                }
            }
            await paginator?.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { paginator = nil }
        }
    }
}
