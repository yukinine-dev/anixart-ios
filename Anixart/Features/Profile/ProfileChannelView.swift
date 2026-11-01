import SwiftUI
import AnixartKit

@MainActor
struct ProfileChannelView: View {
    @Environment(AppEnvironment.self) private var env
    let channelID: Int
    var preloaded: Channel?
    @State private var viewer: ProfileViewerKey?
    @State private var resource = ProfileResource<ChannelResponse>()
    @State private var articles: Paginator<Article>?

    init(channelID: Int, preloaded: Channel? = nil, viewer: ProfileViewerKey? = nil) {
        self.channelID = channelID
        self.preloaded = preloaded?.id == channelID ? preloaded : nil
        _viewer = State(initialValue: viewer)
    }

    private var channel: Channel? { resource.value?.channel ?? preloaded }

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let channel {
                Section {
                    if let cover = AnixartURL.image(channel.cover) {
                        CachedAsyncImage(url: cover, maxPixelSize: 1200) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                            .frame(height: 150).clipped().listRowInsets(EdgeInsets())
                    }
                    ProfileChannelRow(channel: channel)
                    if let description = channel.description, !description.isEmpty {
                        Text(description).font(.ax(.subheadline)).textSelection(.enabled)
                    }
                    if let profileID = channel.blogProfileId {
                        NavigationLink("Открыть профиль автора") { ProfileView(profileID: profileID, viewer: viewer) }
                    }
                }
                if channel.isDeleted == true {
                    StatusMessageView(title: "Канал удалён", systemImage: "rectangle.stack")
                } else if let articles {
                    Section("Записи") {
                        PaginatedContent(paginator: articles, emptyTitle: "Записей пока нет") { article in
                            NavigationLink { ProfileArticleView(articleID: article.id, preloaded: article, viewer: viewer) } label: {
                                ProfileArticlePreviewRow(article: article)
                            }
                        }
                    }
                }
                ProfileSaveError(message: resource.errorMessage)
            } else if viewer == nil || viewer == env.session.viewerKey {
                ProfileResourceState(resource: resource, title: "Не удалось загрузить канал", retry: load)
            }
        }
        .listStyle(.plain)
        .navigationTitle(viewer == env.session.viewerKey ? (channel?.title ?? "Канал") : "Канал")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await load(); await articles?.reload() }
        .task {
            if viewer == nil { viewer = env.session.viewerKey }
            guard let viewer, viewer == env.session.viewerKey else { return }
            await load()
            guard viewer == env.session.viewerKey, !Task.isCancelled else { return }
            if articles == nil {
                let session = env.session
                let id = channelID
                articles = Paginator { page in try await session.sendViewerRequest(ChannelEndpoints.articles(channelID: id, page: page), for: viewer) }
            }
            await articles?.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            guard viewer != current else { return }
            resource.reset()
            articles = nil
        }
    }

    private func load() async {
        guard let viewer, viewer == env.session.viewerKey else { return }
        await resource.load {
            let response = try await env.session.sendViewerRequest(ChannelEndpoints.channel(id: channelID), for: viewer)
            guard response.channel?.id == channelID else {
                throw AnixartError.decoding(message: "Ответ не содержит канал", path: "channel/\(channelID)")
            }
            return response
        }
    }
}

struct ProfileChannelRow: View {
    let channel: Channel
    var body: some View {
        HStack(spacing: 14) {
            Avatar(url: AnixartURL.image(channel.avatar), size: 48)
            VStack(alignment: .leading, spacing: 5) {
                Text(channel.title ?? "Канал").font(.ax(.headline)).foregroundStyle(.primary)
                Text("Подписчиков: \(Format.count(channel.subscriberCount))")
                    .font(.ax(.caption)).foregroundStyle(.secondary)
            }
            if channel.isVerified == true { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.accent) }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

struct ProfileArticlePreviewRow: View {
    let article: Article
    private var text: String {
        let html = article.payload?.blocks?.compactMap { $0.data?.text ?? $0.data?.title }.first ?? "Запись"
        return ArticleInlineParser.parse(html).map(\.text).joined()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(article.isDeleted == true ? "Запись удалена" : text).font(.ax(.body)).foregroundStyle(.primary).lineLimit(5)
            HStack {
                Text(ProfileDate.dateTime(article.creationDate))
                Spacer()
                Label(Format.count(article.commentCount), systemImage: "bubble.left")
                Label(Format.count(article.repostCount), systemImage: "arrowshape.turn.up.left")
                Label(Format.count(article.voteCount), systemImage: "hand.thumbsup")
            }
            .font(.ax(.caption)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}
