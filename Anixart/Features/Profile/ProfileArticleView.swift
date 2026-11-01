import SwiftUI
import UIKit
import AnixartKit

@MainActor
struct ProfileArticleView: View {
    @Environment(AppEnvironment.self) private var env
    let articleID: Int
    var preloaded: Article?
    @State private var viewer: ProfileViewerKey?
    @State private var resource = ProfileResource<ArticleResponse>()
    @State private var comments = ProfileResource<PageableResponse<ProfileComment>>()
    @State private var composer: ProfileCommentDraft
    @State private var gallery: ProfileGalleryPresentation?
    @State private var report: ProfileReportPresentation?
    @State private var showsVoters = false
    @State private var showsReposts = false
    @State private var isVoting = false
    @State private var votingComments = Set<Int>()
    @State private var actionError: String?

    init(articleID: Int, preloaded: Article? = nil, viewer: ProfileViewerKey? = nil) {
        self.articleID = articleID
        self.preloaded = preloaded?.id == articleID ? preloaded : nil
        _viewer = State(initialValue: viewer)
        _composer = State(initialValue: ProfileCommentDraft(viewer: viewer))
    }

    private var article: Article? { resource.value?.article ?? preloaded }
    private var actionsEnabled: Bool { viewer == env.session.viewerKey && resource.value?.article != nil && !resource.isLoading }

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
                            ForEach(Array(blocks.enumerated()), id: \.offset) { offset, block in
                                ProfileArticleBlockView(block: block, articleID: article.id, onOpenMedia: { index in
                                    let urls = ProfileArticleMedia.urls(in: blocks)
                                    let preceding = ProfileArticleMedia.urls(in: Array(blocks.prefix(offset))).count
                                    gallery = ProfileGalleryPresentation(urls: urls, initialIndex: preceding + index)
                                })
                            }
                        }
                        if let repost = article.repostArticle, let originalID = repost.id, originalID != article.id {
                            NavigationLink {
                                ProfileArticleView(articleID: originalID, preloaded: repost.value, viewer: viewer)
                            } label: {
                                Label(repost.value?.isDeleted == true ? "Запись удалена" : "Открыть исходную запись", systemImage: "arrow.2.squarepath")
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        articleActions(article)
                        inlineComments(article)
                    }
                    if let error = resource.errorMessage {
                        StatusMessageView(title: "Не удалось обновить запись", message: error, retry: load)
                    }
                    if let error = actionError ?? composer.errorMessage { ProfileSaveError(message: error) }
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
            Menu {
                if article?.isDeleted != true {
                    Button { showsVoters = true } label: { Label("Оценили", systemImage: "hand.thumbsup") }
                    Button { showsReposts = true } label: { Label("Репостнули", systemImage: "arrowshape.turn.up.left") }
                }
                ShareLink(item: AnixartEnvironment.webBaseURL.appendingPathComponent("article/\(articleID)")) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }
                Button { UIPasteboard.general.url = AnixartEnvironment.webBaseURL.appendingPathComponent("article/\(articleID)") } label: {
                    Label("Скопировать ссылку", systemImage: "link")
                }
                if article?.isDeleted != true, let account = viewer?.account {
                    Button {
                        report = ProfileReportPresentation(kind: .article, entityID: articleID,
                                                           title: "Запись из канала \(article?.channel?.title ?? "пользователя")", account: account)
                    } label: { Label("Пожаловаться", systemImage: "flag") }
                }
            } label: { Image(systemName: "ellipsis") }
            .disabled(!actionsEnabled)
        } }
        .safeAreaInset(edge: .bottom) {
            if viewer == env.session.viewerKey, article?.isDeleted != true {
                ProfileCommentComposer(draft: $composer.message, isSpoiler: $composer.isSpoiler, viewer: viewer,
                                       replyingTo: composer.replyingTo?.profile?.login,
                                       isSending: composer.isSending || !actionsEnabled,
                                       onCancelReply: { composer.replyingTo = nil }, onSend: { Task { await sendComment() } })
            }
        }
        .navigationDestination(isPresented: $showsVoters) {
            if let viewer { ProfileVotersView(source: .article(articleID), viewer: viewer) }
        }
        .navigationDestination(isPresented: $showsReposts) {
            if let viewer { ProfileArticleRepostsView(articleID: articleID, viewer: viewer) }
        }
        .sheet(item: $report) { ProfileReportView(target: $0) }
        .fullScreenCover(item: $gallery) { ProfileImageGalleryView(urls: $0.urls, initialIndex: $0.initialIndex) }
        .refreshable { await load() }
        .task {
            if viewer == nil { viewer = env.session.viewerKey }
            _ = composer.captureViewer(viewer ?? env.session.viewerKey)
            await load()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current {
                resource.reset(); comments.reset(); composer.invalidate(for: current)
                report = nil; gallery = nil; showsVoters = false; showsReposts = false; actionError = nil
            }
        }
    }

    private func load() async {
        guard let viewer, viewer == env.session.viewerKey else { return }
        let response = await resource.load {
            let response = try await env.session.sendViewerRequest(ArticleEndpoints.article(id: articleID), for: viewer)
            guard response.article?.id == articleID else {
                throw AnixartError.decoding(message: "Ответ не содержит запись", path: "article/\(articleID)")
            }
            return response
        }
        if let article = response?.article, article.isDeleted != true {
            await comments.load { try await env.session.sendViewerRequest(ProfileCommentEndpoints.popularArticleComments(articleID: articleID), for: viewer) }
        }
    }

    private func articleActions(_ article: Article) -> some View {
        HStack(spacing: 18) {
            NavigationLink {
                ProfileCommentsAtLocationView(location: .init(category: .articles, parentID: article.id), viewer: viewer)
            } label: { Label(Format.count(article.commentCount), systemImage: "bubble.left") }
            Button { showsReposts = true } label: { Label(Format.count(article.repostCount), systemImage: "arrowshape.turn.up.left") }
            Spacer()
            Button { Task { await voteArticle(-1) } } label: {
                Image(systemName: "chevron.down").foregroundStyle(article.vote == -1 ? Theme.accent : Color.secondary)
            }.accessibilityLabel("Не нравится")
            Text(Format.count(article.voteCount)).monospacedDigit()
            Button { Task { await voteArticle(1) } } label: {
                Image(systemName: "chevron.up").foregroundStyle(article.vote == 1 ? Theme.accent : Color.secondary)
            }.accessibilityLabel("Нравится")
        }
        .font(.ax(.subheadline)).buttonStyle(.plain).disabled(!actionsEnabled || isVoting)
    }

    @ViewBuilder
    private func inlineComments(_ article: Article) -> some View {
        if let response = comments.value {
            if response.items.isEmpty, article.commentCount == 0 {
                Text("Ещё никто не оставлял комментарии. Будьте первыми!").font(.ax(.subheadline)).foregroundStyle(.secondary)
            } else {
                Text("Популярные и актуальные").font(.ax(.headline))
                ForEach(response.items) { comment in
                    ProfileCommentRow(comment: comment, viewer: viewer, onReply: { if !composer.isSending { composer.replyingTo = comment } },
                                      onVote: { value in Task { await voteComment(comment, value) } },
                                      isVoting: votingComments.contains(comment.id), actionsEnabled: actionsEnabled && !composer.isSending,
                                      contextCategory: .articles)
                    if (comment.replyCount ?? 0) > 0 {
                        NavigationLink("Показать \(Plural.replies(comment.replyCount ?? 0))") {
                            ProfileCommentDetailView(commentID: comment.threadRootID, category: .articles,
                                                     preloaded: comment.threadRootID == comment.id ? comment : nil,
                                                     fallbackLocation: .init(category: .articles, parentID: article.id), viewer: viewer)
                        }
                    }
                }
                NavigationLink("Показать все комментарии") {
                    ProfileCommentsAtLocationView(location: .init(category: .articles, parentID: article.id), viewer: viewer)
                }
            }
        } else {
            ProfileResourceState(resource: comments, title: "Не удалось загрузить комментарии", retry: load)
        }
    }

    private func voteArticle(_ value: Int) async {
        guard actionsEnabled, !isVoting, let article, let viewer else { return }
        guard let account = viewer.account else { env.session.promptSignIn(); return }
        isVoting = true
        actionError = nil
        defer { isVoting = false }
        do {
            try await env.session.sendConfirmedAccountRequest(ArticleEndpoints.vote(id: articleID, vote: article.vote == value ? 0 : value), for: account)
            await load()
        } catch { if !ProfileRequestFailure.isCancellation(error) { actionError = Paginator<Release>.message(for: error) } }
    }

    private func voteComment(_ comment: ProfileComment, _ value: Int) async {
        guard actionsEnabled, !votingComments.contains(comment.id), comment.isDeleted != true, comment.canLike != false else { return }
        guard let account = viewer?.account else { env.session.promptSignIn(); return }
        votingComments.insert(comment.id)
        actionError = nil
        defer { votingComments.remove(comment.id) }
        do {
            try await env.session.sendConfirmedAccountRequest(ProfileCommentEndpoints.vote(commentID: comment.id, category: .articles,
                                                                                         vote: comment.vote == value ? 0 : value), for: account)
            await load()
        } catch { if !ProfileRequestFailure.isCancellation(error) { actionError = Paginator<Release>.message(for: error) } }
    }

    private func sendComment() async {
        guard actionsEnabled else { return }
        let reply = composer.replyingTo
        if await composer.send(at: .init(category: .articles, parentID: articleID), parentCommentID: reply?.threadRootID,
                               session: env.session) { await load() }
    }

    private func articleHeader(_ article: Article) -> some View {
        HStack(spacing: 14) {
            Avatar(url: AnixartURL.image(article.channel?.avatar ?? article.author?.avatar), size: 48)
            VStack(alignment: .leading, spacing: 4) {
                if let channel = article.channel {
                    if let owner = channel.blogProfileId {
                        NavigationLink(channel.title ?? "Блог") { ProfileView(profileID: owner, viewer: viewer) }.font(.ax(.headline))
                    } else {
                        NavigationLink(channel.title ?? "Канал") {
                            ProfileChannelView(channelID: channel.id, preloaded: channel, viewer: viewer)
                        }.font(.ax(.headline))
                    }
                } else { Text("Запись").font(.ax(.headline)) }
                if let author = article.author {
                    NavigationLink(author.login ?? "Автор") { ProfileView(profileID: author.id, viewer: viewer) }
                        .font(.ax(.subheadline))
                } else if let profileID = article.channel?.blogProfileId {
                    NavigationLink("Открыть профиль") { ProfileView(profileID: profileID, viewer: viewer) }.font(.ax(.subheadline))
                }
                Text(ProfileDate.dateTime(article.creationDate)).font(.ax(.caption)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

@MainActor
struct ProfileArticleBlockView: View {
    let block: ArticleBlock
    let articleID: Int
    var onOpenMedia: ((Int) -> Void)? = nil
    @State private var gallery: ProfileGalleryPresentation?
    @State private var playsEmbed = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .fullScreenCover(item: $gallery) { ProfileImageGalleryView(urls: $0.urls, initialIndex: $0.initialIndex) }
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
                let valid = files.filter { AnixartURL.image($0.url) != nil }
                VStack(spacing: 4) {
                    if let first = valid.first {
                        mediaButton(first, index: 0, files: valid, large: true)
                    }
                    if valid.count > 1 {
                        HStack(spacing: 4) {
                            ForEach(Array(valid.enumerated().dropFirst().prefix(2)), id: \.offset) { index, file in
                                mediaButton(file, index: index, files: valid, large: false)
                                    .overlay {
                                        if index == 2, valid.count > 3 {
                                            Text("+\(valid.count - 3)").font(.ax(.largeTitle, .bold)).foregroundStyle(.white)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.35))
                                                .allowsHitTesting(false)
                                        }
                                    }
                            }
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

    private func mediaButton(_ file: ArticleMediaFile, index: Int, files: [ArticleMediaFile], large: Bool) -> some View {
        Button {
            if let onOpenMedia { onOpenMedia(index) }
            else { gallery = ProfileGalleryPresentation(urls: files.compactMap { AnixartURL.image($0.url) }, initialIndex: index) }
        } label: {
            CachedAsyncImage(url: AnixartURL.image(file.url), maxPixelSize: large ? 1200 : 600) { $0.resizable().scaledToFill() } placeholder: {
                Rectangle().fill(.quaternary).overlay { ProgressView() }
            }
            .aspectRatio(large ? mediaRatio(file) : 1.35, contentMode: .fit)
            .clipped()
        }
        .buttonStyle(.plain).accessibilityLabel("Открыть изображение \(index + 1)")
    }

    private func mediaRatio(_ file: ArticleMediaFile) -> CGFloat {
        guard let width = file.width, let height = file.height, width > 0, height > 0 else { return 16 / 9 }
        return CGFloat(width) / CGFloat(height)
    }
}

@MainActor
struct ProfileArticleImageView: View {
    let url: URL
    var body: some View {
        ProfileImageGalleryView(urls: [url])
    }
}

enum ProfileArticleMedia {
    static func urls(in blocks: [ArticleBlock]) -> [URL] {
        blocks.flatMap { block -> [URL] in
            guard block.type == "media", case .media(let files)? = block.data?.items else { return [] }
            return files.compactMap { AnixartURL.image($0.url) }
        }
    }
}

@MainActor
struct ProfileArticleRepostsView: View {
    @Environment(AppEnvironment.self) private var env
    let articleID: Int
    let viewer: ProfileViewerKey
    @State private var paginator: Paginator<Article>?

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Нет репостов") { article in
                    NavigationLink { ProfileArticleView(articleID: article.id, preloaded: article, viewer: viewer) } label: {
                        ProfileArticlePreviewRow(article: article)
                    }
                }
            }
        }
        .listStyle(.plain).navigationTitle("Репостнули").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            guard viewer == env.session.viewerKey else { return }
            let session = env.session
            if paginator == nil { paginator = Paginator { page in try await session.sendViewerRequest(ArticleEndpoints.reposts(id: articleID, page: page), for: viewer) } }
            await paginator?.loadFirstPageIfNeeded()
        }
        .refreshable { await paginator?.reload() }
        .onChange(of: env.session.viewerKey) { _, current in if viewer != current { paginator = nil } }
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
