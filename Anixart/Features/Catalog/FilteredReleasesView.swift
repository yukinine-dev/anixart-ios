import SwiftUI
import AnixartKit

/// Shared filter results. Overflow actions use the displayed paginator so an
/// acknowledged list change also updates membership of this filtered result set.
@MainActor
struct FilteredReleasesView: View {
    @Environment(AppEnvironment.self) private var env
    let filter: FilterRequest
    let title: String
    private let suppliedPaginator: Paginator<Release>?
    @State private var viewer: ProfileViewerKey?
    @State private var model: ReleaseFeedModel?
    @State private var opened: Release?
    @State private var actionTarget: Release?

    init(filter: FilterRequest, title: String, viewer: ProfileViewerKey? = nil, paginator: Paginator<Release>? = nil) {
        self.filter = filter
        self.title = title
        self.suppliedPaginator = paginator
        _viewer = State(initialValue: viewer)
    }

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let model, model.hasCurrentViewer {
                PaginatedContent(paginator: model.paginator, emptyTitle: "Ничего не найдено", emptyMessage: "Попробуйте изменить фильтры") { release in
                    ReleaseListRow(release: release) { actionTarget = release }
                        .onTapGesture { opened = release }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await model?.paginator.reload() }
        .navigationDestination(item: $opened) { release in
            ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: viewer)
        }
        .sheet(item: $actionTarget) { release in
            if let viewer, let model { ReleaseQuickActionsSheet(release: release, viewer: viewer, feed: model) }
        }
        .task {
            if viewer == nil { viewer = env.session.viewerKey }
            guard viewer == env.session.viewerKey else { return }
            if model == nil {
                model = ReleaseFeedModel(filter: filter.normalized, session: env.session, paginator: suppliedPaginator)
            }
            await model?.paginator.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { model = nil; actionTarget = nil; opened = nil }
        }
    }
}
