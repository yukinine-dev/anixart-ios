import SwiftUI
import AnixartKit

@MainActor
struct CatalogView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: CatalogViewModel?
    @State private var isShowingFilter = false

    private let columns = [GridItem(.adaptive(minimum: Theme.Poster.gridWidth), spacing: Theme.Spacing.row)]

    var body: some View {
        NavigationStack {
            Group {
                if let model, model.hasCurrentViewer {
                    content(model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Каталог")
            .searchable(
                text: Binding(
                    get: { model?.query ?? "" },
                    set: { model?.query = $0 }
                ),
                prompt: "Название аниме"
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let model { ReleaseSearchScopeMenu(model: model) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingFilter = true
                    } label: {
                        Image(systemName: (model?.activeFilterCount ?? 0) > 0
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $isShowingFilter) {
                if let model {
                    FilterSheet(
                        current: model.filter,
                        onApply: { model.apply(filter: $0) },
                        onReset: { model.resetFilter() }
                    )
                }
            }
            .task(id: env.session.viewerKey) {
                if model?.viewer != env.session.viewerKey {
                    model = CatalogViewModel(session: env.session, filter: model?.filter ?? FilterRequest(),
                                             query: model?.query ?? "", searchScope: model?.searchScope ?? .all)
                    isShowingFilter = false
                }
            }
            // Re-runs (and cancels the previous run) on every keystroke; the debounce
            // lives in `search()`.
            .task(id: model?.searchKey) {
                await model?.search()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: CatalogViewModel) -> some View {
        if model.isShowingSearch {
            ReleaseSearchResultsView(model: model)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.section) {
                    PaginatedContent(
                        paginator: model.browse,
                        emptyTitle: "Ничего не найдено",
                        emptyMessage: "Попробуйте изменить фильтры"
                    ) { release in
                        NavigationLink {
                            ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: model.viewer)
                        } label: {
                            ReleaseCard(release: release)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .refreshable { await model.browse.reload() }
            .task(id: ObjectIdentifier(model.browse)) { await model.browse.loadFirstPageIfNeeded() }
        }
    }
}

/// Everything in one franchise, from `related/{relatedId}/{page}`.
@MainActor
struct RelatedReleasesView: View {
    @Environment(AppEnvironment.self) private var env
    let related: Related
    let context: RelatedReleasesContext
    @State private var viewer: ProfileViewerKey?
    @State private var paginator: Paginator<Release>?
    @State private var opened: Release?
    @State private var actionTarget: Release?

    init(related: Related, viewer: ProfileViewerKey? = nil, context: RelatedReleasesContext = .franchise) {
        self.related = related
        self.context = context
        _viewer = State(initialValue: viewer)
    }

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let paginator {
                if context.showsFranchiseHeader {
                    Section {
                        Text(related.displayName).font(.ax(.title2, .bold))
                        if let description = related.description, !description.isEmpty {
                            Text(description).font(.ax(.subheadline)).textSelection(.enabled)
                        }
                        if let count = related.releaseCountText {
                            Text(count).font(.ax(.caption)).foregroundStyle(.secondary)
                        }
                    }
                }
                PaginatedContent(paginator: paginator, emptyTitle: "Нет связанных релизов") { release in
                    ReleaseListRow(release: release, showsSeasonAndCategory: true) { actionTarget = release }
                        .onTapGesture { opened = release }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(context.title(for: related))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await paginator?.reload() }
        .navigationDestination(item: $opened) { release in
            ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: viewer)
        }
        .sheet(item: $actionTarget) { release in
            if let viewer { ReleaseQuickActionsSheet(release: release, viewer: viewer) }
        }
        .task {
            if viewer == nil { viewer = env.session.viewerKey }
            guard let viewer, viewer == env.session.viewerKey else { return }
            if paginator == nil {
                paginator = BrowsingPaginators.related(relatedID: related.id, viewer: viewer, session: env.session)
            }
            await paginator?.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { paginator = nil; opened = nil; actionTarget = nil }
        }
    }
}

enum RelatedReleasesContext: Equatable {
    case franchise
    case release(Int)

    var showsFranchiseHeader: Bool { self == .franchise }
    func title(for related: Related) -> String {
        showsFranchiseHeader ? related.displayName : "Связанные релизы"
    }
}
