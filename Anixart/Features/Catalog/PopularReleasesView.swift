import SwiftUI
import AnixartKit

/// Android's "Популярное" screen is a ranked feed with four catalogue tabs,
/// rather than an ungrouped filter result.
@MainActor
struct PopularReleasesView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var category: PopularCategory = .ongoing

    var body: some View {
        VStack(spacing: 0) {
            Picker("Раздел", selection: $category) {
                ForEach(PopularCategory.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.vertical, 10)

            PopularReleasesList(filter: category.filter)
        }
        .navigationTitle("Популярное")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum PopularCategory: String, CaseIterable, Identifiable {
    case ongoing
    case completed
    case movies
    case ova

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ongoing: "Онгоинги"
        case .completed: "Завершенные"
        case .movies: "Фильмы"
        case .ova: "OVA"
        }
    }

    var filter: FilterRequest {
        switch self {
        case .ongoing:
            FilterRequest(sort: .popularDescending, status: .ongoing)
        case .completed:
            FilterRequest(sort: .popularDescending, status: .released)
        case .movies:
            FilterRequest(sort: .popularDescending, category: .movie)
        case .ova:
            FilterRequest(sort: .popularDescending, category: .ova)
        }
    }
}

@MainActor
private struct PopularReleasesList: View {
    @Environment(AppEnvironment.self) private var env
    let filter: FilterRequest

    @State private var viewer: ProfileViewerKey?
    @State private var model: ReleaseFeedModel?
    @State private var opened: Release?
    @State private var actionTarget: Release?

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let model, model.hasCurrentViewer {
                PaginatedContent(
                    paginator: model.paginator,
                    emptyTitle: "Ничего не найдено",
                    emptyMessage: "Попробуйте открыть другую вкладку"
                ) { release in
                    HStack(alignment: .top, spacing: 8) {
                        Text(rank(for: release))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .center)
                            .padding(.top, 16)

                        ReleaseListRow(release: release, style: .card) {
                            actionTarget = release
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { opened = release }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await model?.paginator.reload() }
        .navigationDestination(item: $opened) { release in
            ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: viewer)
        }
        .sheet(item: $actionTarget) { release in
            if let viewer, let model {
                ReleaseQuickActionsSheet(release: release, viewer: viewer, feed: model)
            }
        }
        .task(id: ReleaseFeedKey(filter: filter.normalized, viewer: env.session.viewerKey)) {
            viewer = env.session.viewerKey
            model = ReleaseFeedModel(filter: filter.normalized, session: env.session)
            await model?.paginator.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current {
                model = nil
                actionTarget = nil
                opened = nil
            }
        }
    }

    private func rank(for release: Release) -> String {
        guard let index = model?.paginator.items.firstIndex(where: { $0.id == release.id }) else {
            return "—"
        }
        return "\(index + 1)"
    }
}