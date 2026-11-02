import Foundation
import AnixartKit

/// Shared by feed rows, search previews and channel lists. Account writes are
/// explicit, acknowledged, and tied to the viewer that loaded the source row.
@MainActor
@Observable
final class FeedActionsModel {
    let viewer: ProfileViewerKey
    private let session: SessionController
    private(set) var articleUpdates: [Int: Article] = [:]
    private(set) var channelUpdates: [Int: Channel] = [:]
    private(set) var pendingArticles = Set<Int>()
    private(set) var pendingChannels = Set<Int>()
    private(set) var errorMessage: String?
    private(set) var membershipRevision = 0
    private(set) var articleRefreshNeeded = Set<Int>()
    private(set) var blogRequestsSent = Set<Int>()
    private var articleReadRevisions: [Int: Int] = [:]

    init(session: SessionController) { self.session = session; viewer = session.viewerKey }
    var hasCurrentViewer: Bool { viewer == session.viewerKey }
    func article(_ source: Article) -> Article { articleUpdates[source.id] ?? source }
    func channel(_ source: Channel) -> Channel { channelUpdates[source.id] ?? source }

    func subscribe(_ source: Channel, enabled: Bool) async -> Bool {
        guard hasCurrentViewer, source.id > 0, source.isDeleted != true, !pendingChannels.contains(source.id) else { return false }
        guard let account = viewer.account else { session.promptSignIn(); return false }
        let current = channel(source)
        if current.isSubscribed == enabled { return true }
        pendingChannels.insert(source.id)
        errorMessage = nil
        defer { pendingChannels.remove(source.id) }
        do {
            var updated = current
            if current.isBlog == true {
                guard enabled, let profileID = current.blogProfileId, profileID > 0, profileID != account.profileID else {
                    errorMessage = enabled ? "Не удалось определить автора блога." : "Подпиской на блог можно управлять в профиле автора."
                    return false
                }
                // ArticlePresenterDelegate routes blogs through ProfileFriendApi,
                // not ChannelApi. This is a request, not an accepted friendship.
                let response = try await session.sendConfirmedAccountRequest(ProfileEndpoints.sendFriendRequest(to: profileID), for: account)
                if response.friendStatus != .friend { blogRequestsSent.insert(source.id) }
                await session.refreshProfile(for: account)
                guard hasCurrentViewer else { return false }
            } else {
                try await session.sendConfirmedAccountRequest(enabled ? ChannelEndpoints.subscribe(channelID: source.id)
                                                             : ChannelEndpoints.unsubscribe(channelID: source.id), for: account)
            }
            updated.isSubscribed = enabled
            // Subscriber totals are server-owned; never invent a global +1/-1.
            channelUpdates[source.id] = updated
            membershipRevision += 1
            return true
        } catch { record(error); return false }
    }

    func vote(_ source: Article, value: Int) async -> Bool {
        guard hasCurrentViewer, [-1, 1].contains(value), source.id > 0, source.isDeleted != true,
              !pendingArticles.contains(source.id), !articleRefreshNeeded.contains(source.id) else { return false }
        guard let account = viewer.account else { session.promptSignIn(); return false }
        let current = article(source)
        let desired = current.vote == value ? 0 : value
        pendingArticles.insert(source.id)
        errorMessage = nil
        defer { pendingArticles.remove(source.id) }
        do {
            try await session.sendConfirmedAccountRequest(ArticleEndpoints.vote(id: source.id, vote: desired), for: account)
            var acknowledged = current
            acknowledged.vote = desired
            articleUpdates[source.id] = acknowledged
            articleRefreshNeeded.insert(source.id)
            await refreshArticle(id: source.id)
            return true
        } catch { record(error); return false }
    }

    /// Retry a supplementary read, never resend an already acknowledged vote.
    func refreshArticle(id: Int) async {
        guard hasCurrentViewer, id > 0 else { return }
        let revision = (articleReadRevisions[id] ?? 0) + 1
        articleReadRevisions[id] = revision
        do {
            let response = try await session.sendViewerRequest(ArticleEndpoints.article(id: id), for: viewer)
            guard let article = response.article, article.id == id else {
                throw AnixartError.decoding(message: "Не удалось обновить запись", path: "article/\(id)")
            }
            guard articleReadRevisions[id] == revision else { return }
            articleUpdates[id] = article
            articleRefreshNeeded.remove(id)
            errorMessage = nil
        } catch { if articleReadRevisions[id] == revision { record(error) } }
    }

    func hideArticle(_ source: Article) async -> Bool {
        guard hasCurrentViewer, source.id > 0, source.isDeleted != true, !pendingArticles.contains(source.id) else { return false }
        guard let account = viewer.account else { session.promptSignIn(); return false }
        pendingArticles.insert(source.id)
        errorMessage = nil
        defer { pendingArticles.remove(source.id) }
        do {
            try await session.sendConfirmedAccountRequest(ArticleEndpoints.hide(id: source.id), for: account)
            membershipRevision += 1
            return true
        } catch { record(error); return false }
    }

    func hideChannel(_ source: Channel) async -> Bool {
        guard hasCurrentViewer, source.id > 0, source.isDeleted != true, !pendingChannels.contains(source.id) else { return false }
        guard let account = viewer.account else { session.promptSignIn(); return false }
        pendingChannels.insert(source.id)
        errorMessage = nil
        defer { pendingChannels.remove(source.id) }
        do {
            try await session.sendConfirmedAccountRequest(ChannelEndpoints.hide(channelID: source.id), for: account)
            membershipRevision += 1
            return true
        } catch { record(error); return false }
    }

    private func record(_ error: any Error) {
        if hasCurrentViewer, !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Article>.message(for: error) }
    }
}
