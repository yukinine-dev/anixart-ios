import SwiftUI
import AnixartKit

@MainActor
struct ProfileBlogSection: View {
    @Environment(AppEnvironment.self) private var env
    let profile: Profile
    let channel: Channel?
    let viewer: ProfileViewerKey?
    let errorMessage: String?
    var retry: () async -> Void
    @State private var articles: Paginator<Article>?
    @State private var showsCreateInfo = false
    @State private var showsUpgradeDialog = false

    private var ownsProfile: Bool { viewer == env.session.viewerKey && viewer?.account?.profileID == profile.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if ownsProfile {
                Button {
                    let minimum = ProfileCapabilities.minimumBlogReputation(toggles: env.session.toggles)
                    if ProfileBlogEntryPolicy.requiresUpgrade(profile: profile, channel: channel, minimum: minimum) { showsUpgradeDialog = true }
                    else { showsCreateInfo = true }
                } label: {
                    Label("Добавить запись…", systemImage: "square.and.pencil")
                        .font(.ax(.body)).frame(maxWidth: .infinity, alignment: .leading).padding()
                }
                .buttonStyle(.plain)
            }
            if let channel, channel.isDeleted != true, let articles {
                PaginatedContent(paginator: articles, emptyTitle: "Записей пока нет") { article in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(channel.title ?? profile.displayLogin).font(.ax(.headline))
                        NavigationLink { ProfileArticleView(articleID: article.id, preloaded: article, viewer: viewer) } label: {
                            ProfileArticlePreviewRow(article: article)
                        }
                        .buttonStyle(.plain)
                        if let media = article.payload?.blocks?.first(where: { $0.type == "media" }) {
                            ProfileArticleBlockView(block: media, articleID: article.id)
                        }
                        Divider()
                    }
                    .padding(.horizontal)
                }
            }
            if let errorMessage {
                StatusMessageView(title: "Не удалось загрузить блог", message: errorMessage, retry: retry)
            }
        }
        .padding(.top, 24)
        .task(id: channel?.id) {
            articles = nil
            guard let channel, channel.isDeleted != true, let viewer, viewer == env.session.viewerKey else { return }
            let session = env.session
            let list = Paginator<Article> { page in
                try await session.sendViewerRequest(ChannelEndpoints.articles(channelID: channel.id, page: page), for: viewer)
            }
            articles = list
            await list.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.profileRevision) { _, _ in
            if viewer == env.session.viewerKey { Task { await articles?.reload() } }
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { articles = nil; showsCreateInfo = false; showsUpgradeDialog = false }
        }
        .fullScreenCover(isPresented: $showsUpgradeDialog) {
            ProfileBlogUpgradeDialog(score: profile.ratingScore ?? 0,
                                     minimum: ProfileCapabilities.minimumBlogReputation(toggles: env.session.toggles))
        }
        .sheet(isPresented: $showsCreateInfo) {
            // Do not create a blog merely by opening this information.
            ProfileHelpSheet(title: "Добавить запись", paragraphs: [
                "Просмотр записей доступен. Создание и редактирование записей в клиенте iOS пока не поддерживаются.",
                "Существующий блог и обложка остаются доступны независимо от текущего уровня репутации."
            ])
        }
    }
}
