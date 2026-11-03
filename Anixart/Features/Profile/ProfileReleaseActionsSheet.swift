import SwiftUI
import AnixartKit

struct ProfileReleaseActionPresentation: Identifiable {
    let id = UUID()
    let release: Release
    let viewer: ProfileViewerKey
    var includesHistoryRemoval = false
}

/// Public list rows belong to the owner. Actions must first fetch the release
/// for the viewer, so the owner's watch status is never edited as if it were ours.
@MainActor
struct ProfileReleaseActionsSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let target: ProfileReleaseActionPresentation
    @State private var model: ReleaseDetailViewModel?
    @State private var showsStatuses = false
    @State private var confirmsHistoryRemoval = false
    @State private var historyError: String?
    @State private var isRemovingHistory = false

    var body: some View {
        NavigationStack {
            List {
                ProfileViewerNotice(viewer: target.viewer)
                if target.viewer == env.session.viewerKey {
                    Section { Text(target.release.displayTitle).font(.ax(.headline)) }
                    if let model, let release = model.release {
                        Section {
                            Button { Task { await model.toggleFavorite() } } label: {
                                Label(release.isFavorite == true ? "Убрать из избранного" : "Добавить в избранное", systemImage: "bookmark")
                            }
                            Button { showsStatuses = true } label: {
                                Label("Мой статус: \(release.profileListStatus.flatMap(ProfileListStatus.init(rawValue:))?.title ?? "Не смотрю")", systemImage: "list.bullet")
                            }
                            NavigationLink { ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: target.viewer) } label: {
                                Label("Перейти к релизу", systemImage: "arrow.right")
                            }
                            if target.includesHistoryRemoval, target.viewer.account != nil {
                                Button("Удалить из истории просмотра", role: .destructive) { confirmsHistoryRemoval = true }
                            }
                        }
                        .disabled(model.isLoading || model.isPerformingAction || isRemovingHistory)
                        if let error = model.actionError ?? historyError { ProfileSaveError(message: error) }
                    } else if let model, let error = model.errorMessage {
                        StatusMessageView(title: "Не удалось загрузить мой статус", message: error, retry: { await model.load() })
                    } else { ProgressView().frame(maxWidth: .infinity).padding() }
                }
            }
            .navigationTitle("Действия с релизом")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .task {
            guard target.viewer == env.session.viewerKey else { return }
            if model == nil {
                model = ReleaseDetailViewModel(releaseID: target.release.id, preloaded: nil, session: env.session, viewer: target.viewer)
            }
            await model?.load()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if target.viewer != current { model?.invalidate(); showsStatuses = false; confirmsHistoryRemoval = false }
        }
        .confirmationDialog("Мой статус", isPresented: $showsStatuses, titleVisibility: .visible) {
            ForEach(ProfileListStatus.allCases) { status in
                Button(status.title) { Task { await model?.setList(status) } }
            }
            Button("Не смотрю") { Task { await model?.setList(nil) } }
            Button("Отмена", role: .cancel) { }
        }
        .confirmationDialog("Удалить из истории просмотра?", isPresented: $confirmsHistoryRemoval, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { await removeHistory() } }
        }
    }

    private func removeHistory() async {
        guard !isRemovingHistory, target.includesHistoryRemoval, target.viewer == env.session.viewerKey,
              let account = target.viewer.account else { return }
        isRemovingHistory = true
        defer { isRemovingHistory = false }
        do {
            try await env.session.sendConfirmedAccountRequest(BookmarkEndpoints.removeFromHistory(releaseID: target.release.id), for: account)
            await env.session.refreshProfile(for: account)
            if target.viewer == env.session.viewerKey { dismiss() }
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { historyError = Paginator<Release>.message(for: error) }
        }
    }
}
