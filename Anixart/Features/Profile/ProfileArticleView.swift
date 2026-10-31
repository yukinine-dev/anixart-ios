import SwiftUI
import AnixartKit

@MainActor
struct ProfileArticleView: View {
    @Environment(AppEnvironment.self) private var env
    let articleID: Int
    var preloaded: Article?
    @State private var viewer: ProfileViewerKey?
    @State private var resource = ProfileResource<ArticleResponse>()

    init(articleID: Int, preloaded: Article? = nil, viewer: ProfileViewerKey? = nil) {
        self.articleID = articleID
        self.preloaded = preloaded?.id == articleID ? preloaded : nil
        _viewer = State(initialValue: viewer)
    }

    private var article: Article? { resource.value?.article ?? preloaded }

    var body: some View {
        ScrollView {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let article {
                VStack(alignment: .leading, spacing: 24) {
                    articleHeader(article)
                    if article.isDeleted == true {
                        StatusMessageView(title: "Запись удалена", systemImage: "doc")
                    } else {
                        if let blocks = article.payload?.blocks, !blocks.isEmpty {
                            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                                ProfileArticleBlockView(block: block, articleID: article.id)
                            }
                        }
                        if let repost = article.repostArticle, let originalID = repost.id, originalID != article.id {
                            NavigationLink {
                                ProfileArticleView(articleID: originalID, preloaded: repost.value, viewer: viewer)
                            } label: {
                                Label("Открыть исходную запись", systemImage: "arrow.2.squarepath")
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        NavigationLink {
                            ProfileCommentsAtLocationView(location: ProfileCommentLocation(category: .articles, parentID: article.id), viewer: viewer)
                        } label: {
                            Label("Комментарии · \(Format.count(article.commentCount))", systemImage: "bubble.left")
                                .font(.ax(.headline)).padding(.vertical, 12)
                        }
                    }
                    if let error = resource.errorMessage {
                        StatusMessageView(title: "Не удалось обновить запись", message: error, retry: load)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if viewer == nil || viewer == env.session.viewerKey {
                ProfileResourceState(resource: resource, title: "Не удалось загрузить запись", retry: load)
            }
        }
        .navigationTitle("Запись")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            ShareLink(item: AnixartEnvironment.webBaseURL.appendingPathComponent("article/\(articleID)")) {
                Image(systemName: "square.and.arrow.up")
            }
        } }
        .refreshable { await load() }
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
        await resource.load {
            let response = try await env.session.sendViewerRequest(ArticleEndpoints.article(id: articleID), for: viewer)
            guard response.article?.id == articleID else {
                throw AnixartError.decoding(message: "Ответ не содержит запись", path: "article/\(articleID)")
            }
            return response
        }
    }

    private func articleHeader(_ article: Article) -> some View {
        HStack(spacing: 14) {
            Avatar(url: AnixartURL.image(article.channel?.avatar ?? article.author?.avatar), size: 48)
            VStack(alignment: .leading, spacing: 4) {
                if let channel = article.channel {
                    NavigationLink(channel.title ?? "Канал") {
                        ProfileChannelView(channelID: channel.id, preloaded: channel, viewer: viewer)
                    }.font(.ax(.headline))
                } else { Text("Запись").font(.ax(.headline)) }
                if let author = article.author {
                    NavigationLink(author.login ?? "Автор") { ProfileView(profileID: author.id, viewer: viewer) }
                        .font(.ax(.subheadline))
                } else if let profileID = article.channel?.blogProfileId {
                    NavigationLink("Открыть профиль") { ProfileView(profileID: profileID, viewer: viewer) }.font(.ax(.subheadline))
                }
                Text(ProfileDate.text(article.creationDate)).font(.ax(.caption)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

@MainActor
struct ProfileArticleBlockView: View {
    let block: ArticleBlock
    let articleID: Int
    @State private var imageURL: URL?
    @State private var playsEmbed = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheet(isPresented: Binding(get: { imageURL != nil }, set: { if !$0 { imageURL = nil } })) {
                if let imageURL { ProfileArticleImageView(url: imageURL) }
            }
            .fullScreenCover(isPresented: $playsEmbed) {
                if let url = embedURL { WebPlayerSheet(url: url, title: block.data?.title ?? "Видео") }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch block.type {
        case "paragraph":
            ArticleInlineText(html: block.data?.text ?? "")
        case "header":
            ArticleInlineText(html: block.data?.text ?? "", style: (block.data?.level ?? 2) <= 2 ? .title2 : .headline, weight: .bold)
                .accessibilityAddTraits(.isHeader)
        case "quote":
            VStack(alignment: block.data?.alignment == "center" ? .center : .leading, spacing: 10) {
                ArticleInlineText(html: block.data?.text ?? "").italic()
                if let caption = block.data?.caption, !caption.isEmpty {
                    ArticleInlineText(html: caption, style: .caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: block.data?.alignment == "center" ? .center : .leading)
            .padding(16).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        case "delimiter":
            HStack { Spacer(); Text("• • •").font(.ax(.title2)).foregroundStyle(.tertiary); Spacer() }.padding(.vertical, 10)
        case "list":
            if case .list(let items)? = block.data?.items {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, text in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(block.data?.style == "ordered" ? "\(index + 1)." : "•").font(.ax(.body))
                            ArticleInlineText(html: text)
                        }
                    }
                }
            }
        case "media":
            if case .media(let files)? = block.data?.items {
                VStack(spacing: 12) {
                    ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                        if let url = AnixartURL.image(file.url) {
                            Button { imageURL = url } label: {
                                CachedAsyncImage(url: url, maxPixelSize: 1600) { $0.resizable().scaledToFit() } placeholder: {
                                    Rectangle().fill(.quaternary).aspectRatio(mediaRatio(file), contentMode: .fit).overlay { ProgressView() }
                                }
                                .frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Открыть изображение")
                        }
                    }
                }
            }
        case "embed":
            VStack(alignment: .leading, spacing: 12) {
                if let image = AnixartURL.image(block.data?.image) {
                    CachedAsyncImage(url: image, maxPixelSize: 1200) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                if let title = block.data?.title { ArticleInlineText(html: title, style: .headline) }
                if let description = block.data?.description { ArticleInlineText(html: description, style: .subheadline).foregroundStyle(.secondary) }
                if embedURL != nil, block.data?.service != nil {
                    Button { playsEmbed = true } label: { Label("Воспроизвести", systemImage: "play.fill") }
                        .buttonStyle(.bordered)
                } else if let url = ProfileWebURL.url(block.data?.url) {
                    Link(destination: url) { Label(block.data?.siteName ?? "Открыть ссылку", systemImage: "link") }
                }
            }
            .padding(16).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("Этот блок пока не поддерживается").font(.ax(.subheadline)).foregroundStyle(.secondary)
                Link("Открыть запись на сайте", destination: AnixartEnvironment.webBaseURL.appendingPathComponent("article/\(articleID)"))
                    .font(.ax(.subheadline))
            }
            .padding(16).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var embedURL: URL? { ProfileWebURL.url(block.data?.embed) ?? ProfileWebURL.url(block.data?.url) }

    private func mediaRatio(_ file: ArticleMediaFile) -> CGFloat {
        guard let width = file.width, let height = file.height, width > 0, height > 0 else { return 16 / 9 }
        return CGFloat(width) / CGFloat(height)
    }
}

@MainActor
struct ProfileArticleImageView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    var body: some View {
        NavigationStack {
            ScrollView {
                CachedAsyncImage(url: url, maxPixelSize: 2400) { $0.resizable().scaledToFit() } placeholder: { ProgressView().padding(80) }
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle("Изображение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") } }
            }
        }
    }
}

enum ProfileWebURL {
    static func url(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
}
