import Foundation

/// The original FeedApi/SearchApi routes. Personal feed is not the public Fresh
/// feed, and neither route is a catalogue or release-filter request.
public enum FeedEndpoints {
    public static func my(page: Int, filter: FeedFilter = FeedFilter()) -> Endpoint<PageableResponse<Article>> {
        Endpoint(path: "feed/all/\(page)",
                 query: ["channel_id": filter.channelID.map { String($0) }, "date": String(filter.date)], auth: .required)
    }

    public static func fresh(page: Int) -> Endpoint<PageableResponse<Article>> {
        // Unlike search/feed, the live API rejects an anonymous Fresh read (401).
        Endpoint(path: "feed/latest/all/\(page)", auth: .required)
    }

    public static func latestArticle() -> Endpoint<LatestArticleResponse> {
        Endpoint(path: "feed/latest", auth: .required)
    }

    public static func search(_ query: String, page: Int) -> Endpoint<FeedSearchResponse> {
        Endpoint(method: .post, path: "search/feed/\(page)", body: .json(SearchRequest(query: query)))
    }

    public static func searchArticles(_ request: ArticlesSearchRequest, page: Int) -> Endpoint<PageableResponse<Article>> {
        Endpoint(method: .post, path: "search/articles/\(page)", body: .json(request))
    }
}
