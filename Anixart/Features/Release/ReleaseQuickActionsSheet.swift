import SwiftUI
import AnixartKit

/// The search/franchise row menu, verified on the original phone. The release's
/// own viewer status is read before writes; this is not a franchise CRUD route.
@MainActor
struct ReleaseQuickActionsSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let release: Release
    let viewer: ProfileViewerKey
    let feed: ReleaseFeedModel?
    @State private var model: ReleaseDetailViewModel?
    @State private var showsStatuses = false

    init(release: Release, viewer: ProfileViewerKey, feed: ReleaseFeedModel? = nil) {
        self.release = release
        self.viewer = viewer
        self.feed = feed
    }

    private var currentRelease: Release? {
        if let feed { return feed.viewer == viewer && feed.actionRelease?.id == release.id ? feed.actionRelease : nil }
        return model?.release
    }
    private var isBusy: Bool { feed.map { $0.isPerformingAction || $0.isLoadingActionRelease } ?? (model?.isLoading == true || model?.isPerformingAction == true) }
    private var loadError: String? {
        if let feed { return feed.actionLoadError ?? (feed.paginator.failedPage == 0 ? feed.paginator.errorMessage : nil) }
        return model?.errorMessage
    }
    private var actionError: String? { feed == nil ? model?.actionError : feed?.actionError }

    var body: some View {
        NavigationStack {
            List {
                ProfileViewerNotice(viewer: viewer)
                if viewer == env.session.viewerKey, feed == nil || feed?.viewer == viewer {
                    Section {
                        Text(release.displayTitle).font(.ax(.headline))
                        HStack(spacing: 8) {
                            if let episodes = release.episodeProgressText { Text(episodes) }
                            if let rating = release.ratingText { Label(rating, systemImage: "star.fill") }
                        }
                        .font(.ax(.subheadline)).foregroundStyle(.secondary)
                    }
                    if let current = currentRelease {
                        Section {
                            Button { Task { await toggleFavorite() } } label: {
                                Label(current.isFavorite == true ? "Убрать из избранного" : "Добавить в избранное", systemImage: "bookmark")
                            }
                            Button { showsStatuses = true } label: {
                                Label("В списке: \(current.listStatus?.title ?? "не смотрю")", systemImage: "list.bullet")
                            }
                        }
                        .disabled(isBusy || loadError != nil)
                        if let error = loadError {
                            StatusMessageView(title: "Не удалось обновить данные релиза", message: error, retry: load)
                        } else if let error = actionError {
                            Text(error).font(.ax(.subheadline)).foregroundStyle(.red)
                        }
                    } else if let error = loadError {
                        StatusMessageView(title: "Не удалось загрузить мой статус", message: error, retry: load)
                    } else { ProgressView().frame(maxWidth: .infinity) }
                }
            }
            .navigationTitle("Действия с релизом")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .task {
            guard viewer == env.session.viewerKey else { return }
            await load()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { model?.invalidate(); showsStatuses = false }
        }
        .sheet(isPresented: Binding(get: { feed != nil && showsStatuses }, set: { showsStatuses = $0 })) {
            if let feed, let current = currentRelease { HomeReleaseListSheet(release: current, model: feed) }
        }
        .confirmationDialog("Выберите статус просмотра", isPresented: Binding(get: { feed == nil && showsStatuses }, set: { showsStatuses = $0 }), titleVisibility: .visible) {
            Button("Не смотрю") { Task { await model?.setList(nil) } }
            ForEach(ProfileListStatus.allCases) { status in
                Button(status.title) { Task { await model?.setList(status) } }
            }
            Button("Отмена", role: .cancel) { }
        }
    }

    private func load() async {
        guard viewer == env.session.viewerKey else { return }
        if let feed {
            guard feed.viewer == viewer else { return }
            await feed.loadActionRelease(releaseID: release.id)
            if feed.paginator.failedPage == 0 { await feed.paginator.retry() }
        } else {
            if model == nil { model = ReleaseDetailViewModel(releaseID: release.id, preloaded: nil, session: env.session, viewer: viewer) }
            await model?.load()
        }
    }

    private func toggleFavorite() async {
        if let feed { await feed.toggleFavorite(releaseID: release.id) }
        else { await model?.toggleFavorite() }
    }
}
