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
                if let model {
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
            .task {
                if model == nil { model = CatalogViewModel(client: env.client) }
                await model?.browse.loadFirstPageIfNeeded()
            }
            // Re-runs (and cancels the previous run) on every keystroke; the debounce
            // lives in `search()`.
            .task(id: model?.query) {
                await model?.search()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: CatalogViewModel) -> some View {
        if model.isShowingSearch {
            searchResults(model)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.section) {
                    PaginatedContent(
                        paginator: model.browse,
                        emptyTitle: "Ничего не найдено",
                        emptyMessage: "Попробуйте изменить фильтры"
                    ) { release in
                        NavigationLink {
                            ReleaseDetailView(releaseID: release.id, preloaded: release)
                        } label: {
                            ReleaseCard(release: release)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .refreshable { await model.browse.reload() }
        }
    }

    @ViewBuilder
    private func searchResults(_ model: CatalogViewModel) -> some View {
        List {
            if model.isSearching && model.searchResults.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let error = model.searchError {
                StatusMessageView(title: "Поиск не удался", message: error, systemImage: "wifi.exclamationmark")
            } else if model.searchResults.isEmpty {
                StatusMessageView(
                    title: "Ничего не найдено",
                    message: "Проверьте написание названия",
                    systemImage: "magnifyingglass"
                )
            } else {
                if let related = model.relatedSuggestion, let name = related.nameRu {
                    Section("Франшиза") {
                        NavigationLink {
                            RelatedReleasesView(related: related)
                        } label: {
                            Label(name, systemImage: "rectangle.stack")
                        }
                    }
                }
                Section {
                    ForEach(model.searchResults) { release in
                        NavigationLink {
                            ReleaseDetailView(releaseID: release.id, preloaded: release)
                        } label: {
                            ReleaseRow(release: release)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

/// Everything in one franchise, from `related/{relatedId}/{page}`.
@MainActor
struct RelatedReleasesView: View {
    @Environment(AppEnvironment.self) private var env
    let related: Related
    @State private var viewer: ProfileViewerKey?
    @State private var paginator: Paginator<Release>?

    init(related: Related, viewer: ProfileViewerKey? = nil) {
        self.related = related
        _viewer = State(initialValue: viewer)
    }

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Нет связанных релизов") { release in
                    NavigationLink {
                        ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: viewer)
                    } label: {
                        RelatedReleaseRow(release: release)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(related.nameRu ?? "Франшиза")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await paginator?.reload() }
        .task {
            if viewer == nil { viewer = env.session.viewerKey }
            guard let viewer, viewer == env.session.viewerKey else { return }
            if paginator == nil {
                let session = env.session
                let relatedID = related.id
                paginator = Paginator { page in
                    try await session.sendViewerRequest(ReleaseEndpoints.related(relatedID: relatedID, page: page), for: viewer)
                }
            }
            await paginator?.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { paginator = nil }
        }
    }
}
