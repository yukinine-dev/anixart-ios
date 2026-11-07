import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class FeedStateTests: XCTestCase {
    private func page(_ ids: [Int]) -> String {
        let rows = ids.map { "{\"id\":\($0)}" }.joined(separator: ",")
        return "{\"code\":0,\"content\":[\(rows)],\"current_page\":0,\"total_page_count\":0}"
    }

    private func search(_ ids: [Int], channelID: Int = 17) -> String {
        let rows = ids.map { "{\"id\":\($0)}" }.joined(separator: ",")
        return "{\"code\":0,\"channels\":{\"content\":[{\"id\":\(channelID)}],\"total_count\":10},\"blogs\":{\"content\":[],\"total_count\":21},\"articles\":{\"content\":[\(rows)],\"total_count\":5081}}"
    }

    private func token(_ request: URLRequest) -> String? {
        request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.first { $0.name == "token" }?.value
    }

    @MainActor
    func testRootTabsAreFourSectionsPlusSearchAndOriginalFeedSections() {
        XCTAssertEqual(RootView.Tab.allCases.map(\.title), ["Главная", "Обзор", "Закладки", "Лента", "Поиск"])
        XCTAssertEqual(FeedTab.allCases.map(\.title), ["Моя лента", "Свежее", "Управляемые"])
        XCTAssertEqual(FeedTab.visibleTabs(signedIn: false), [.my, .fresh])
        XCTAssertEqual(FeedTab.visibleTabs(signedIn: true), [.my, .fresh, .managed])
    }

    @MainActor
    func testGuestFeedNeverDispatchesAuthenticatedTimelineReads() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let model = FeedViewModel(session: rig.session)
        await model.load(.my)
        await model.load(.fresh)
        await model.load(.managed)
        XCTAssertTrue(rig.api.requests.isEmpty)
        XCTAssertFalse(rig.session.isPresentingAuth, "Opening the tab shows a prompt; it does not force login")
    }

    @MainActor
    func testFreshPagingUsesRaw25RatherThanZeroMetadataOrDeduplicatedCount() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = FeedTimelineModel(kind: .fresh, session: rig.session)
        rig.api.enqueue("/feed/latest/all/0", json: page(Array(1...24) + [24]))
        rig.api.enqueue("/feed/latest/all/1", json: page([24, 25]))
        await model.paginator.loadFirstPageIfNeeded()
        XCTAssertEqual(model.paginator.items.count, 24)
        XCTAssertTrue(model.paginator.hasMore)
        await model.paginator.loadNextPage()
        XCTAssertEqual(model.paginator.items.map(\.id), Array(1...25))
        XCTAssertFalse(model.paginator.hasMore)
    }

    @MainActor
    func testFilterReplacementDoesNotMixOldAndNewChannelPeriodPages() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = FeedTimelineModel(kind: .my, session: rig.session)
        let retired = model.paginator
        let held = rig.api.hold("/feed/all/0")
        defer { held.respond("{}", status: 500) }
        let loading = Task { await retired.loadFirstPageIfNeeded() }
        defer { loading.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        model.apply(filter: FeedFilter(channelID: 71, date: 2))
        rig.api.enqueue("/feed/all/0", json: page([201]))
        await model.paginator.loadFirstPageIfNeeded()
        held.respond(page([101]))
        await loading.value
        XCTAssertEqual(model.paginator.items.map(\.id), [201])
        let request = try XCTUnwrap(rig.api.requests(to: "/feed/all/0").last)
        XCTAssertTrue(request.url?.query?.contains("channel_id=71") == true)
        XCTAssertTrue(request.url?.query?.contains("date=2") == true)
        model.apply(filter: FeedFilter(date: 1_790_863_500))
        XCTAssertEqual(model.filter.date, 2, "Period presets must never turn into epoch timestamps")
    }

    @MainActor
    func testMissingFeedContentIsFailureNotAnEmptyFeed() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = FeedTimelineModel(kind: .fresh, session: rig.session)
        rig.api.enqueue("/feed/latest/all/0", json: #"{"code":0}"#)
        await model.paginator.loadFirstPageIfNeeded()
        XCTAssertNotNil(model.paginator.errorMessage)
        rig.api.enqueue("/feed/latest/all/0", json: page([]))
        await model.paginator.retry()
        XCTAssertNil(model.paginator.errorMessage)
        XCTAssertTrue(model.paginator.isEmpty)
    }

    @MainActor
    func testAnUnrequestedPageIsNotConfusedWithASuccessfullyLoadedEmptyPage() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = FeedTimelineModel(kind: .fresh, session: rig.session)
        XCTAssertFalse(model.paginator.hasLoaded)
        XCTAssertFalse(model.paginator.isEmpty)
        rig.api.enqueue("/feed/latest/all/0", json: page([]))
        await model.paginator.loadFirstPageIfNeeded()
        XCTAssertTrue(model.paginator.hasLoaded)
        XCTAssertTrue(model.paginator.isEmpty)
    }

    @MainActor
    func testNewPostCheckDoesNotReplaceOrAutomaticallyRefreshVisiblePosts() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = FeedTimelineModel(kind: .fresh, session: rig.session)
        rig.api.enqueue("/feed/latest/all/0", json: page([71]))
        await model.paginator.loadFirstPageIfNeeded()
        rig.api.enqueue("/feed/latest", json: #"{"code":0,"articleId":72}"#)
        await model.checkForUpdates()
        XCTAssertTrue(model.hasNewArticles)
        XCTAssertEqual(model.paginator.items.map(\.id), [71])
        XCTAssertEqual(rig.api.requests(to: "/feed/latest/all/0").count, 1)
        rig.api.enqueue("/feed/latest/all/0", json: page([72]))
        await model.reload()
        XCTAssertFalse(model.hasNewArticles)
        XCTAssertEqual(model.paginator.items.map(\.id), [72])
    }

    @MainActor
    func testLateNewPostCheckCannotRestoreTheBadgeAfterAnExplicitRefresh() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = FeedTimelineModel(kind: .fresh, session: rig.session)
        rig.api.enqueue("/feed/latest/all/0", json: page([71]))
        await model.paginator.loadFirstPageIfNeeded()
        let held = rig.api.hold("/feed/latest")
        defer { held.respond("{}", status: 500) }
        let checking = Task { await model.checkForUpdates() }
        defer { checking.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        rig.api.enqueue("/feed/latest/all/0", json: page([72]))
        await model.reload()
        held.respond(#"{"code":0,"articleId":73}"#)
        await checking.value
        XCTAssertFalse(model.hasNewArticles)
    }

    @MainActor
    func testGuestSearchKeepsNestedCountsAndFirstPagePreviewDuringPaging() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let model = FeedSearchModel(query: " anime ", session: rig.session)
        rig.api.enqueue("/search/feed/0", json: search(Array(1...25)))
        rig.api.enqueue("/search/feed/1", json: search([26], channelID: 999))
        await model.load(debounce: false)
        await model.articles.loadNextPage()
        XCTAssertEqual(model.query, "anime")
        XCTAssertEqual(model.metadata.channels?.items.map(\.id), [17])
        XCTAssertEqual(model.metadata.channels?.totalCount, 10)
        XCTAssertEqual(model.metadata.blogs?.totalCount, 21)
        XCTAssertEqual(model.articles.totalCount, 5081)
        XCTAssertEqual(model.articles.items.map(\.id), Array(1...26))
        XCTAssertNil(token(try XCTUnwrap(rig.api.requests(to: "/search/feed/0").first)))
    }

    @MainActor
    func testStaleSearchRefreshCannotReplaceNewArticlesOrChannelPreviews() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let model = FeedSearchModel(query: "anime", session: rig.session)
        let held = rig.api.hold("/search/feed/0")
        defer { held.respond("{}", status: 500) }
        let old = Task { await model.reload() }
        defer { old.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        rig.api.enqueue("/search/feed/0", json: search([202], channelID: 22))
        await model.reload()
        held.respond(search([101], channelID: 11))
        await old.value
        XCTAssertEqual(model.metadata.channels?.items.map(\.id), [22])
        XCTAssertEqual(model.articles.items.map(\.id), [202])
    }

    @MainActor
    func testMissingSearchEnvelopeCanRetryWithoutReportingZeroResults() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let model = FeedSearchModel(query: "anime", session: rig.session)
        rig.api.enqueue("/search/feed/0", json: #"{"code":0}"#)
        await model.load(debounce: false)
        XCTAssertNotNil(model.articles.errorMessage)
        XCTAssertFalse(model.metadata.hasLoaded)
        rig.api.enqueue("/search/feed/0", json: search([]))
        await model.articles.retry()
        XCTAssertNil(model.articles.errorMessage)
        XCTAssertTrue(model.metadata.hasLoaded)
    }

    @MainActor
    func testSubscriptionAndManagedPagingKeepTheirDifferentRawSizes() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let subscriptions = FeedChannelListModel(kind: .subscriptions, session: rig.session)
        rig.api.enqueue("/channel/subscription/all/0", json: page(Array(1...30)))
        await subscriptions.paginator.loadFirstPageIfNeeded()
        XCTAssertTrue(subscriptions.paginator.hasMore)
        let managed = FeedChannelListModel(kind: .managed(onlySubscribed: true), session: rig.session)
        rig.api.enqueue("/channel/all/0", json: page(Array(1...25)))
        await managed.paginator.loadFirstPageIfNeeded()
        XCTAssertTrue(managed.paginator.hasMore)
        let request = try XCTUnwrap(rig.api.requests(to: "/channel/all/0").first)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["permission"] as? Int, 1)
        XCTAssertEqual(body["is_subscribed"] as? Bool, true)
    }

    @MainActor
    func testOldFeedAndSearchCannotReadWithANewerLogin() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "first")
        let feed = FeedTimelineModel(kind: .fresh, session: rig.session)
        let search = FeedSearchModel(query: "anime", session: rig.session)
        try await rig.signIn(token: "second")
        let count = rig.api.requests.count
        await feed.reload()
        await search.reload()
        await feed.paginator.loadFirstPageIfNeeded()
        XCTAssertEqual(rig.api.requests.count, count)
        XCTAssertFalse(feed.hasCurrentViewer)
        XCTAssertFalse(search.hasCurrentViewer)
    }

    @MainActor
    func testBlogNavigationUsesProfileIDNotChannelIDAndRetainsViewerInRoute() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "first")
        let channel = try profileTestDecode(Channel.self, #"{"id":17,"is_blog":true,"blog_profile_id":71}"#)
        XCTAssertEqual(FeedChannelNavigation.route(for: channel), .profile(71))
        let unknown = try profileTestDecode(Channel.self, #"{"id":17,"is_blog":true}"#)
        XCTAssertEqual(FeedChannelNavigation.route(for: unknown), .channel(unknown))
        let old = FeedRouteContext(route: .channel(channel), viewer: rig.session.viewerKey)
        try await rig.signIn(token: "second")
        let current = FeedRouteContext(route: .channel(channel), viewer: rig.session.viewerKey)
        XCTAssertNotEqual(old, current)
        XCTAssertEqual(Set([old, current]).count, 2)
    }
}
