import Foundation
import XCTest
@testable import AnixartKit

final class FeedContractTests: XCTestCase {
    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    func testPersonalFeedUsesChannelAndPeriodWithoutCatalogueFields() async throws {
        let client = AnixartClient(tokenStore: InMemoryTokenStore(token: "owner", profileID: 42))
        let request = try await client.urlRequest(for: FeedEndpoints.my(page: 2, filter: FeedFilter(channelID: 71, date: FeedDatePeriod.week.rawValue)))
        XCTAssertEqual(request.url?.path, "/feed/all/2")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first { $0.name == "channel_id" }?.value, "71")
        XCTAssertEqual(query?.first { $0.name == "date" }?.value, "2")
        XCTAssertEqual(query?.first { $0.name == "token" }?.value, "owner")
        XCTAssertNil(query?.first { $0.name == "category_id" })
    }

    func testDefaultFeedPeriodIsLatestAndIsNotATimestamp() async throws {
        let client = AnixartClient(tokenStore: InMemoryTokenStore(token: "owner", profileID: 42))
        let request = try await client.urlRequest(for: FeedEndpoints.my(page: 0))
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first { $0.name == "date" }?.value, "0")
        XCTAssertNil(query?.first { $0.name == "channel_id" })
        XCTAssertEqual(FeedDatePeriod.allCases.map(\.rawValue), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(FeedDatePeriod.allCases.map(\.title), ["Последнее", "24 часа", "Неделя", "Месяц", "Год", "Всё время"])
        XCTAssertNil(FeedFilter(date: 5).validationMessage)
        XCTAssertNotNil(FeedFilter(date: 1_790_863_500).validationMessage)
        XCTAssertNotNil(FeedFilter(channelID: 0).validationMessage)
    }

    func testFreshAndLatestAreDistinctAuthenticatedReadEndpoints() async throws {
        let client = AnixartClient(tokenStore: InMemoryTokenStore(token: "owner", profileID: 42))
        let fresh = try await client.urlRequest(for: FeedEndpoints.fresh(page: 3))
        let latest = try await client.urlRequest(for: FeedEndpoints.latestArticle())
        XCTAssertEqual(fresh.url?.path, "/feed/latest/all/3")
        XCTAssertEqual(latest.url?.path, "/feed/latest")
        XCTAssertEqual(fresh.httpMethod, "GET")
        XCTAssertEqual(latest.httpMethod, "GET")
        XCTAssertNil(fresh.httpBody)
        let guest = AnixartClient(tokenStore: InMemoryTokenStore())
        do { _ = try await guest.urlRequest(for: FeedEndpoints.fresh(page: 0)); XCTFail("Fresh requires login") }
        catch { XCTAssertEqual(error as? AnixartError, .notAuthenticated(path: "feed/latest/all/0")) }
        do { _ = try await guest.urlRequest(for: FeedEndpoints.latestArticle()); XCTFail("Latest requires login") }
        catch { XCTAssertEqual(error as? AnixartError, .notAuthenticated(path: "feed/latest")) }
    }

    func testGuestFeedSearchUsesTheOriginalSearchBodyAndNoToken() async throws {
        let client = AnixartClient(tokenStore: InMemoryTokenStore())
        let request = try await client.urlRequest(for: FeedEndpoints.search("anime", page: 0))
        XCTAssertEqual(request.url?.path, "/search/feed/0")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(try jsonBody(request)["query"] as? String, "anime")
        XCTAssertEqual(try jsonBody(request)["searchBy"] as? Int, 0)
        XCTAssertNil(try jsonBody(request)["search_by"])
        XCTAssertNil(request.url?.query)
    }

    func testSearchResponsePreservesThreeIndependentNestedPagesAndCounts() throws {
        let response = try decode(FeedSearchResponse.self, #"""
        {"code":0,"channels":{"content":[{"id":1}],"total_count":10},
         "blogs":{"content":[{"id":2,"is_blog":true}],"total_count":21},
         "articles":{"content":[{"id":3,"payload":{"blocks":[]}}],"total_count":5081},
         "tags":{"content":["anime"]}}
        """#)
        XCTAssertEqual(response.channels?.items.map(\.id), [1])
        XCTAssertEqual(response.blogs?.items.map(\.id), [2])
        XCTAssertEqual(response.articles?.items.map(\.id), [3])
        XCTAssertEqual(response.channels?.totalCount, 10)
        XCTAssertEqual(response.blogs?.totalCount, 21)
        XCTAssertEqual(response.articles?.totalCount, 5081)
        XCTAssertEqual(response.tags?.items, ["anime"])
        XCTAssertNil(try decode(FeedSearchResponse.self, #"{"code":0}"#).articles)
    }

    func testLatestArticleIDKeepsCamelCase() throws {
        XCTAssertEqual(try decode(LatestArticleResponse.self, #"{"code":0,"articleId":71}"#).articleId, 71)
        XCTAssertNil(try decode(LatestArticleResponse.self, #"{"code":0,"article_id":71}"#).articleId)
        XCTAssertEqual(try decode(SubscriptionCountResponse.self, #"{"code":0,"subscription_count":5}"#).subscriptionCount, 5)
    }

    func testManagedChannelsHaveTheirOwnFilterBodyAndNoSearchQuery() async throws {
        let client = AnixartClient(tokenStore: InMemoryTokenStore(token: "owner", profileID: 42))
        let request = try await client.urlRequest(for: ChannelEndpoints.all(page: 1, request: ChannelsFilterRequest(
            permission: 1, sort: 1, isBlog: false, isSubscribed: true)))
        XCTAssertEqual(request.url?.path, "/channel/all/1")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try jsonBody(request)
        XCTAssertEqual(body["permission"] as? Int, 1)
        XCTAssertEqual(body["sort"] as? Int, 1)
        XCTAssertEqual(body["is_blog"] as? Bool, false)
        XCTAssertEqual(body["is_subscribed"] as? Bool, true)
        XCTAssertNil(body["query"])
        XCTAssertNil(body["isBlog"])
    }

    func testChannelsAndBlogsSearchUseBooleanFilterNotPermissionOrTitleScope() async throws {
        let client = AnixartClient(tokenStore: InMemoryTokenStore())
        for isBlog in [false, true] {
            let request = try await client.urlRequest(for: ChannelEndpoints.search(ChannelsSearchRequest(query: "anime", isBlog: isBlog), page: 2))
            XCTAssertEqual(request.url?.path, "/search/channels/2")
            XCTAssertEqual(try jsonBody(request)["is_blog"] as? Bool, isBlog)
            XCTAssertEqual(try jsonBody(request)["query"] as? String, "anime")
            XCTAssertNil(try jsonBody(request)["permission"])
            XCTAssertNil(try jsonBody(request)["is_subscribed"])
            XCTAssertNil(try jsonBody(request)["searchBy"])
        }
    }

    func testArticleSearchUsesASeparateChannelIDBody() async throws {
        let client = AnixartClient(tokenStore: InMemoryTokenStore())
        let request = try await client.urlRequest(for: FeedEndpoints.searchArticles(ArticlesSearchRequest(query: "anime"), page: 0))
        XCTAssertEqual(request.url?.path, "/search/articles/0")
        XCTAssertEqual(try jsonBody(request)["channel_id"] as? Int, 0)
        XCTAssertEqual(try jsonBody(request)["query"] as? String, "anime")
        XCTAssertNil(try jsonBody(request)["channelId"])
    }

    func testFeedMutationsKeepTheOriginalMethodsAndPaths() async throws {
        let client = AnixartClient(tokenStore: InMemoryTokenStore(token: "owner", profileID: 42))
        let examples: [(Endpoint<StatusResponse>, String, String)] = [
            (ChannelEndpoints.subscribe(channelID: 71), "/channel/subscribe/71", "POST"),
            (ChannelEndpoints.unsubscribe(channelID: 71), "/channel/unsubscribe/71", "POST"),
            (ChannelEndpoints.hide(channelID: 71), "/channel/mute/71", "POST"),
            (ArticleEndpoints.hide(id: 81), "/article/mute/81", "GET"),
            (ArticleEndpoints.unhide(id: 81), "/article/unmute/81", "GET")
        ]
        for (endpoint, path, method) in examples {
            let request = try await client.urlRequest(for: endpoint)
            XCTAssertEqual(request.url?.path, path)
            XCTAssertEqual(request.httpMethod, method)
            XCTAssertTrue(request.url?.query?.contains("token=owner") == true)
        }
    }
}
