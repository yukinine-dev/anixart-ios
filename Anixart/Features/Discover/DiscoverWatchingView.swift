import SwiftUI
import AnixartKit

/// Full-screen version of the Android `watching_now` block from Обзор.
/// The overview keeps a compact first page; this screen owns the complete list
/// and requests further pages only as the user reaches the end.
@MainActor
struct DiscoverWatchingView: View {
    @Environment(AppEnvironment.self) private var env
    let viewer: ProfileViewerKey

    @State private var paginator: Paginator<Release>?
    @State private var opened: Release?
    @State private var actionTarget: Release?

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let paginator {
                PaginatedContent(
                    paginator: paginator,
                    emptyTitle: "Пока никто не смотрит",
                    emptyMessage: "Здесь появятся тайтлы, которые сейчас смотрят пользователи"
                ) { release in
                    ReleaseListRow(release: release, style: .plain) { actionTarget = release }
                        .onTapGesture { opened = release }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 12))
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Смотрят сейчас")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await paginator?.reload() }
        .navigationDestination(item: $opened) { release in
            ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: viewer)
        }
        .sheet(item: $actionTarget) { release in
            if viewer == env.session.viewerKey {
                ReleaseQuickActionsSheet(release: release, viewer: viewer)
            }
        }
        .task(id: viewer) {
            guard viewer == env.session.viewerKey else { return }
            if paginator == nil {
                let session = env.session
                paginator = Paginator(rawPageSize: 25) { page in
                    try await session.sendViewerRequest(DiscoverEndpoints.watching(page: page), for: viewer)
                }
            }
            await paginator?.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if current != viewer {
                paginator = nil
                opened = nil
                actionTarget = nil
            }
        }
    }
}