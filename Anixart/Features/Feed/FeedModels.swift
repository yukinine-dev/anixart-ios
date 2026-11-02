import Foundation
import AnixartKit

enum FeedTab: String, CaseIterable, Hashable, Identifiable {
    case my, fresh, managed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .my: return "Моя лента"
        case .fresh: return "Свежее"
        case .managed: return "Управляемые"
        }
    }
    static func visibleTabs(signedIn: Bool) -> [FeedTab] { signedIn ? allCases : [.my, .fresh] }
}

@MainActor
enum FeedPageValidation {
    static func articles(_ page: PageableResponse<Article>, path: String) throws -> PageableResponse<Article> {
        if let code = page.code, code != 0 { throw AnixartError.api(code: code, path: path) }
        guard let rows = page.content, rows.allSatisfy({ $0.id > 0 }) else {
            throw AnixartError.decoding(message: "Сервер не вернул список записей", path: path)
        }
        return page
    }
    static func channels(_ page: PageableResponse<Channel>, path: String) throws -> PageableResponse<Channel> {
        if let code = page.code, code != 0 { throw AnixartError.api(code: code, path: path) }
        guard let rows = page.content, rows.allSatisfy({ $0.id > 0 }) else {
            throw AnixartError.decoding(message: "Сервер не вернул список каналов", path: path)
        }
        return page
    }
}

@MainActor
@Observable
final class FeedTimelineModel {
    enum Kind: Hashable, Sendable { case my, fresh }
    let kind: Kind
    let viewer: ProfileViewerKey
    private let session: SessionController
    private(set) var filter: FeedFilter
    private(set) var paginator: Paginator<Article>
    private(set) var hasNewArticles = false
    private(set) var updateError: String?
    private var updateGeneration = 0

    init(kind: Kind, session: SessionController, filter: FeedFilter = FeedFilter()) {
        self.kind = kind
        self.session = session
        viewer = session.viewerKey
        let effectiveFilter = kind == .my ? filter : FeedFilter()
        self.filter = effectiveFilter
        paginator = Self.makePaginator(kind: kind, filter: effectiveFilter, viewer: session.viewerKey, session: session)
    }

    var hasCurrentViewer: Bool { viewer == session.viewerKey }

    func apply(filter: FeedFilter) {
        guard hasCurrentViewer, kind == .my, filter.validationMessage == nil, filter != self.filter else { return }
        updateGeneration += 1
        self.filter = filter
        paginator = Self.makePaginator(kind: kind, filter: filter, viewer: viewer, session: session)
    }

    func reload() async {
        guard hasCurrentViewer else { return }
        updateGeneration += 1
        let current = paginator
        await current.reload()
        guard hasCurrentViewer, current === paginator, current.failedPage == nil else { return }
        hasNewArticles = false
        updateError = nil
    }

    /// The APK's Fresh tab checks feed/latest every 120 seconds. The view owns
    /// that cancellable active-scene task; checks never refresh/scroll on their own.
    func checkForUpdates() async {
        guard hasCurrentViewer, kind == .fresh, viewer.account != nil, !paginator.items.isEmpty else { return }
        updateGeneration += 1
        let revision = updateGeneration
        let current = paginator
        do {
            let response = try await session.sendViewerRequest(FeedEndpoints.latestArticle(), for: viewer)
            guard let id = response.articleId, id > 0 else {
                throw AnixartError.decoding(message: "Сервер не вернул последнюю запись", path: "feed/latest")
            }
            guard revision == updateGeneration, current === paginator else { return }
            hasNewArticles = !current.items.contains { $0.id == id }
            updateError = nil
        } catch {
            if revision == updateGeneration, hasCurrentViewer, !ProfileRequestFailure.isCancellation(error) {
                updateError = Paginator<Article>.message(for: error)
            }
        }
    }

    private static func makePaginator(kind: Kind, filter: FeedFilter, viewer: ProfileViewerKey, session: SessionController) -> Paginator<Article> {
        // The response callbacks in both Feed presenters use the raw 25 boundary.
        Paginator(rawPageSize: 25) { page in
            if let message = filter.validationMessage { throw AnixartError.decoding(message: message, path: "feed/all/\(page)") }
            let endpoint = kind == .my ? FeedEndpoints.my(page: page, filter: filter) : FeedEndpoints.fresh(page: page)
            let response = try await session.sendViewerRequest(endpoint, for: viewer)
            return try await FeedPageValidation.articles(response, path: endpoint.path)
        }
    }
}

@MainActor
@Observable
final class FeedChannelListModel {
    enum Kind: Hashable, Sendable {
        case subscriptions
        case recommendations
        case managed(onlySubscribed: Bool)
        case search(query: String, isBlog: Bool)

        var title: String {
            switch self {
            case .subscriptions: return "Мои подписки"
            case .recommendations: return "Каналы"
            case .managed: return "Управляемые"
            case .search(_, let isBlog): return isBlog ? "Блоги" : "Каналы"
            }
        }

        var requiresAccount: Bool {
            switch self {
            case .subscriptions, .managed: return true
            case .recommendations, .search: return false
            }
        }

        func endpoint(page: Int) -> Endpoint<PageableResponse<Channel>> {
            switch self {
            case .subscriptions: return ChannelEndpoints.subscriptions(page: page, sort: 1)
            case .recommendations: return ChannelEndpoints.recommendations(page: page)
            case .managed(let onlySubscribed):
                return ChannelEndpoints.all(page: page, request: ChannelsFilterRequest(
                    permission: 1, sort: 1, isBlog: false, isSubscribed: onlySubscribed ? true : nil))
            case .search(let query, let isBlog):
                return ChannelEndpoints.search(ChannelsSearchRequest(query: query, isBlog: isBlog), page: page)
            }
        }
    }

    let kind: Kind
    let viewer: ProfileViewerKey
    let paginator: Paginator<Channel>
    private let session: SessionController

    init(kind: Kind, session: SessionController) {
        self.kind = kind
        self.session = session
        let viewer = session.viewerKey
        self.viewer = viewer
        // Subscriptions/recommendations use 30; ordinary/managed channel lists
        // and channel search use 25. Never count after deduplication.
        let pageSize: Int
        switch kind { case .subscriptions, .recommendations: pageSize = 30; default: pageSize = 25 }
        paginator = Paginator(rawPageSize: pageSize) { page in
            let endpoint = kind.endpoint(page: page)
            let response = try await session.sendViewerRequest(endpoint, for: viewer)
            return try await FeedPageValidation.channels(response, path: endpoint.path)
        }
    }

    var hasCurrentViewer: Bool { viewer == session.viewerKey }
    func reload() async { if hasCurrentViewer { await paginator.reload() } }
}

@MainActor
@Observable
final class FeedViewModel {
    let viewer: ProfileViewerKey
    let my: FeedTimelineModel
    let fresh: FeedTimelineModel
    let subscriptions: FeedChannelListModel
    let recommendations: FeedChannelListModel
    let subscriptionCount = ProfileResource<SubscriptionCountResponse>()
    let actions: FeedActionsModel
    private let session: SessionController
    private(set) var managed: FeedChannelListModel

    init(session: SessionController) {
        self.session = session
        viewer = session.viewerKey
        my = FeedTimelineModel(kind: .my, session: session)
        fresh = FeedTimelineModel(kind: .fresh, session: session)
        subscriptions = FeedChannelListModel(kind: .subscriptions, session: session)
        recommendations = FeedChannelListModel(kind: .recommendations, session: session)
        managed = FeedChannelListModel(kind: .managed(onlySubscribed: true), session: session)
        actions = FeedActionsModel(session: session)
    }

    var hasCurrentViewer: Bool { viewer == session.viewerKey }

    func setManagedFilter(onlySubscribed: Bool) {
        guard hasCurrentViewer, managed.kind != .managed(onlySubscribed: onlySubscribed) else { return }
        managed = FeedChannelListModel(kind: .managed(onlySubscribed: onlySubscribed), session: session)
    }

    func load(_ tab: FeedTab) async {
        guard hasCurrentViewer, viewer.account != nil else { return }
        switch tab {
        case .fresh: await fresh.paginator.loadFirstPageIfNeeded()
        case .managed: await managed.paginator.loadFirstPageIfNeeded()
        case .my:
            async let posts: Void = my.paginator.loadFirstPageIfNeeded()
            async let channels: Void = subscriptions.paginator.loadFirstPageIfNeeded()
            _ = await (posts, channels)
            if !subscriptionCount.hasAttemptedLoad {
                await subscriptionCount.load { try await session.sendViewerRequest(ChannelEndpoints.subscriptionCount(), for: viewer) }
            }
            if subscriptionCount.value?.subscriptionCount == 0 {
                await recommendations.paginator.loadFirstPageIfNeeded()
            }
        }
    }

    func rebaseAfterMembershipChange() async {
        guard hasCurrentViewer, viewer.account != nil else { return }
        async let mine: Void = my.reload()
        async let latest: Void = fresh.reload()
        async let channels: Void = subscriptions.reload()
        async let owned: Void = managed.reload()
        _ = await (mine, latest, channels, owned)
        await subscriptionCount.load { try await session.sendViewerRequest(ChannelEndpoints.subscriptionCount(), for: viewer) }
    }
}
