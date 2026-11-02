import SwiftUI
import AnixartKit

@MainActor
struct FeedSearchView: View {
    @Environment(AppEnvironment.self) private var env
    let viewer: ProfileViewerKey
    let actions: FeedActionsModel
    @State private var query = ""
    @State private var model: FeedSearchModel?

    private var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if viewer != env.session.viewerKey { ProfileViewerNotice(viewer: viewer) }
                else if normalizedQuery.isEmpty {
                    StatusMessageView(title: "Поиск записей, блогов и каналов", message: "Введите запрос", systemImage: "magnifyingglass")
                } else if let model, model.query == normalizedQuery, model.hasCurrentViewer {
                    searchContent(model)
                } else { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40) }
            }.padding(.vertical, 12)
        }
        .navigationTitle("Поиск").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск записей и блогов")
        .refreshable { await model?.reload() }
        .task(id: normalizedQuery) {
            guard viewer == env.session.viewerKey, !normalizedQuery.isEmpty else { model = nil; return }
            if model?.query != normalizedQuery { model = FeedSearchModel(query: normalizedQuery, session: env.session) }
            await model?.load()
        }
        .onChange(of: env.session.viewerKey) { _, current in if current != viewer { model = nil } }
        .onChange(of: actions.membershipRevision) { _, _ in Task { await model?.reload() } }
    }

    @ViewBuilder
    private func searchContent(_ model: FeedSearchModel) -> some View {
        if let error = actions.errorMessage { Text(error).font(.ax(.subheadline)).foregroundStyle(.red).padding(.horizontal) }
        if let channels = model.metadata.channels {
            channelSection("Каналы", page: channels, model: model, isBlog: false)
        }
        if let blogs = model.metadata.blogs {
            channelSection("Блоги", page: blogs, model: model, isBlog: true)
        }
        if model.metadata.hasLoaded {
            HStack {
                Text("Записи").font(.ax(.title3, .semibold))
                if let count = model.articles.totalCount { Text(Format.count(count)).font(.ax(.subheadline)).foregroundStyle(.secondary) }
                Spacer()
            }.padding(.horizontal)
        }
        PaginatedContent(paginator: model.articles, emptyTitle: "Записей не найдено", emptyMessage: "Попробуйте другой запрос") { article in
            FeedArticleRow(source: article, actions: actions, showsAbsoluteDate: true)
        }
    }

    private func channelSection(_ title: String, page: PageableResponse<Channel>, model: FeedSearchModel, isBlog: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.ax(.title3, .semibold))
                if let count = page.totalCount { Text(Format.count(count)).font(.ax(.subheadline)).foregroundStyle(.secondary) }
                Spacer()
                NavigationLink("Показать все", value: FeedRouteContext(route: .channelSearch(model.query, isBlog: isBlog), viewer: viewer))
                    .font(.ax(.subheadline, .medium))
            }.padding(.horizontal)
            if page.items.isEmpty { Text("Ничего не найдено").font(.ax(.subheadline)).foregroundStyle(.secondary).padding(.horizontal) }
            else { FeedChannelCarousel(channels: page.items, viewer: viewer, actions: actions) }
        }
    }
}
