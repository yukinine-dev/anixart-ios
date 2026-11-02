import SwiftUI
import UIKit
import AnixartKit

/// The original feed renders full-width post blocks, not release cards. Header,
/// media, comments and votes are separate controls so a nested button cannot be
/// swallowed by a surrounding NavigationLink.
@MainActor
struct FeedArticleRow: View {
    @Environment(AppEnvironment.self) private var env
    let source: Article
    let actions: FeedActionsModel
    var showsAbsoluteDate = false
    @State private var showsMore = false
    @State private var gallery: ProfileGalleryPresentation?

    private var article: Article { actions.article(source) }
    private var blocks: [ArticleBlock] { article.payload?.blocks ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header.padding(.horizontal, 16)
            if article.isDeleted == true {
                Text("Запись удалена").font(.ax(.subheadline)).foregroundStyle(.secondary).padding(.horizontal, 16)
            } else {
                ForEach(Array(blocks.prefix(3).enumerated()), id: \.offset) { offset, block in
                    ProfileArticleBlockView(block: block, articleID: article.id, onOpenMedia: { index in
                        let preceding = ProfileArticleMedia.urls(in: Array(blocks.prefix(offset))).count
                        gallery = ProfileGalleryPresentation(urls: ProfileArticleMedia.urls(in: blocks), initialIndex: preceding + index)
                    })
                    .lineLimit(5)
                    .padding(.horizontal, block.type == "media" ? 0 : 16)
                }
                if let repost = article.repostArticle, let originalID = repost.id, originalID != article.id {
                    NavigationLink(value: FeedRouteContext(route: repost.value.map(FeedRoute.article) ?? .articleID(originalID), viewer: actions.viewer)) {
                        Label(repost.value?.isDeleted == true ? "Запись удалена" : "Открыть исходную запись", systemImage: "arrowshape.turn.up.left")
                            .font(.ax(.subheadline)).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).padding(.horizontal, 16)
                }
                NavigationLink(value: FeedRouteContext(route: .article(article), viewer: actions.viewer)) {
                    Text("Показать ещё").font(.ax(.subheadline, .medium)).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.horizontal, 16)
                footer.padding(.horizontal, 16)
                if actions.articleRefreshNeeded.contains(article.id) {
                    Button("Повторить обновление записи") { Task { await actions.refreshArticle(id: article.id) } }
                        .font(.ax(.caption)).padding(.horizontal, 16)
                        .disabled(actions.pendingArticles.contains(article.id))
                }
            }
            Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 8)
        }
        .padding(.top, 16)
        .sheet(isPresented: $showsMore) { FeedArticleMoreSheet(source: article, actions: actions) }
        .fullScreenCover(item: $gallery) { ProfileImageGalleryView(urls: $0.urls, initialIndex: $0.initialIndex) }
        .onChange(of: env.session.viewerKey) { _, current in if actions.viewer != current { showsMore = false; gallery = nil } }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let source = article.channel {
                let channel = actions.channel(source)
                NavigationLink(value: FeedRouteContext(route: FeedChannelNavigation.route(for: channel), viewer: actions.viewer)) {
                    HStack(spacing: 12) {
                        Avatar(url: AnixartURL.image(channel.avatar), size: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Text(channel.title ?? "Канал").font(.ax(.subheadline, .medium)).lineLimit(1)
                                if channel.isVerified == true { Image(systemName: "checkmark.seal.fill").font(.ax(.caption)).foregroundStyle(Theme.accent) }
                            }
                            if let timestamp = article.creationDate, timestamp > 0 {
                                let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
                                Text((showsAbsoluteDate ? Format.dateTime(date) : Format.relativeDate(date)) ?? "")
                                    .font(.ax(.caption)).foregroundStyle(.secondary)
                            }
                        }
                    }.foregroundStyle(.primary).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
                if channel.isSubscribed != true {
                    FeedSubscribeButton(channel: channel, actions: actions)
                } else if actions.blogRequestsSent.contains(channel.id) {
                    Text("Заявка отправлена").font(.ax(.caption)).foregroundStyle(.secondary)
                }
            } else {
                Text("Запись").font(.ax(.headline))
                Spacer()
            }
            Button { showsMore = true } label: {
                Image(systemName: "ellipsis").rotationEffect(.degrees(90)).frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Действия с записью").disabled(!actions.hasCurrentViewer)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            NavigationLink(value: FeedRouteContext(route: .comments(article.id), viewer: actions.viewer)) {
                Label(Format.count(article.commentCount), systemImage: "bubble.left")
                    .padding(.horizontal, 10).padding(.vertical, 7).background(.quaternary, in: Capsule())
            }.buttonStyle(.plain)
            NavigationLink(value: FeedRouteContext(route: .reposts(article.id), viewer: actions.viewer)) {
                Label(Format.count(article.repostCount), systemImage: "arrowshape.turn.up.left")
                    .padding(.horizontal, 10).padding(.vertical, 7).background(.quaternary, in: Capsule())
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
            voteButton(-1, symbol: "chevron.down")
            Text(Format.count(article.voteCount)).monospacedDigit()
            voteButton(1, symbol: "chevron.up")
        }.font(.ax(.subheadline)).foregroundStyle(.secondary)
    }

    private func voteButton(_ value: Int, symbol: String) -> some View {
        Button { Task { _ = await actions.vote(article, value: value) } } label: {
            Image(systemName: symbol).foregroundStyle(article.vote == value ? Theme.accent : Color.secondary)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
        .accessibilityLabel(value == 1 ? "Нравится" : "Не нравится")
        .disabled(!actions.hasCurrentViewer || actions.pendingArticles.contains(article.id) || actions.articleRefreshNeeded.contains(article.id))
    }

}

@MainActor
private struct FeedArticleMoreSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let source: Article
    let actions: FeedActionsModel
    @State private var confirmsHide = false
    @State private var confirmsChannelHide = false
    @State private var confirmsUnsubscribe = false
    @State private var report: ProfileReportPresentation?

    private var article: Article { actions.article(source) }
    private var channel: Channel? { article.channel.map { actions.channel($0) } }

    var body: some View {
        NavigationStack {
            List {
                ProfileViewerNotice(viewer: actions.viewer)
                if actions.hasCurrentViewer {
                    Section {
                        NavigationLink("Открыть запись", value: FeedRouteContext(route: .article(article), viewer: actions.viewer))
                        NavigationLink("Оценили", value: FeedRouteContext(route: .voters(article.id), viewer: actions.viewer))
                        NavigationLink("Репостнули", value: FeedRouteContext(route: .reposts(article.id), viewer: actions.viewer))
                        ShareLink(item: AnixartEnvironment.webBaseURL.appendingPathComponent("article/\(article.id)")) {
                            Label("Поделиться", systemImage: "square.and.arrow.up")
                        }
                        Button("Скопировать ссылку") { UIPasteboard.general.url = AnixartEnvironment.webBaseURL.appendingPathComponent("article/\(article.id)") }
                    }
                    if let channel {
                        Section {
                            NavigationLink("Информация о канале", value: FeedRouteContext(route: .channel(channel), viewer: actions.viewer))
                            if channel.isSubscribed == true {
                                if channel.isBlog == true {
                                    NavigationLink("Управлять подпиской в профиле автора", value: FeedRouteContext(route: FeedChannelNavigation.route(for: channel), viewer: actions.viewer))
                                } else { Button("Отписаться") { confirmsUnsubscribe = true } }
                            } else { FeedSubscribeButton(channel: channel, actions: actions) }
                            if actions.viewer.account != nil { Button(channel.isBlog == true ? "Скрыть блог из ленты" : "Скрыть канал") { confirmsChannelHide = true } }
                        }.disabled(actions.pendingChannels.contains(channel.id))
                    }
                    if article.isDeleted != true, let account = actions.viewer.account {
                        Section {
                            Button("Скрыть запись") { confirmsHide = true }
                            Button("Пожаловаться") {
                                report = ProfileReportPresentation(kind: .article, entityID: article.id,
                                                                   title: "Запись из канала \(channel?.title ?? "пользователя")", account: account)
                            }
                        }.disabled(actions.pendingArticles.contains(article.id))
                    }
                    if let error = actions.errorMessage { Text(error).font(.ax(.subheadline)).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Действия с записью").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .navigationDestination(for: FeedRouteContext.self) { FeedDestinationView(context: $0, actions: actions) }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $report) { ProfileReportView(target: $0) }
        .confirmationDialog("Скрыть запись?", isPresented: $confirmsHide, titleVisibility: .visible) {
            Button("Скрыть запись", role: .destructive) { Task { if await actions.hideArticle(article) { dismiss() } } }
            Button("Отмена", role: .cancel) { }
        } message: { Text("Запись перестанет отображаться в ленте, а также в поиске. Вы уверены, что хотите скрыть запись?") }
        .confirmationDialog(channel?.isBlog == true ? "Скрыть блог?" : "Скрыть канал?", isPresented: $confirmsChannelHide, titleVisibility: .visible) {
            if let channel { Button("Скрыть", role: .destructive) { Task { if await actions.hideChannel(channel) { dismiss() } } } }
            Button("Отмена", role: .cancel) { }
        } message: { Text("Записи перестанут отображаться в ленте и поиске. Действие можно отменить в настройках профиля.") }
        .confirmationDialog("Отписаться?", isPresented: $confirmsUnsubscribe, titleVisibility: .visible) {
            if let channel { Button("Отписаться") { Task { _ = await actions.subscribe(channel, enabled: false) } } }
            Button("Отмена", role: .cancel) { }
        }
        .onChange(of: env.session.viewerKey) { _, current in if current != actions.viewer { report = nil; dismiss() } }
    }
}
