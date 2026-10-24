import Foundation

/// `filter/*`, `search/*`, `schedule`, `discover/*` -- everything for browsing.
public enum CatalogEndpoints {
    /// The catalogue. Despite being a POST this is a read: the filter travels in
    /// the body because it is far too large for a query string.
    public static func filter(
        _ request: FilterRequest,
        page: Int,
        extended: Bool = false
    ) -> Endpoint<PageableResponse<Release>> {
        Endpoint(
            method: .post,
            path: "filter/\(page)",
            query: ["extended_mode": String(extended)],
            body: .json(request)
        )
    }

    public static func searchReleases(
        _ query: String,
        page: Int,
        scope: SearchScope = .all
    ) -> Endpoint<ReleaseSearchResponse> {
        Endpoint(
            method: .post,
            path: "search/releases/\(page)",
            body: .json(SearchRequest(query: query, scope: scope))
        )
    }

    public static func searchProfiles(_ query: String, page: Int) -> Endpoint<PageableResponse<Profile>> {
        Endpoint(method: .post, path: "search/profiles/\(page)", body: .json(SearchRequest(query: query)))
    }

    public static func searchCollections(_ query: String, page: Int) -> Endpoint<PageableResponse<ReleaseCollection>> {
        Endpoint(method: .post, path: "search/collections/\(page)", body: .json(SearchRequest(query: query)))
    }

    /// Searches inside the user's own favourites.
    public static func searchFavorites(_ query: String, page: Int) -> Endpoint<PageableResponse<Release>> {
        Endpoint(
            method: .post,
            path: "search/favorites/\(page)",
            body: .json(SearchRequest(query: query)),
            auth: .required
        )
    }

    /// Searches inside one of the user's watch lists.
    public static func searchList(
        _ query: String,
        status: ProfileListStatus,
        page: Int
    ) -> Endpoint<PageableResponse<Release>> {
        Endpoint(
            method: .post,
            path: "search/profile/list/\(status.rawValue)/\(page)",
            body: .json(SearchRequest(query: query)),
            auth: .required
        )
    }

    public static func searchHistory(_ query: String, page: Int) -> Endpoint<PageableResponse<Release>> {
        Endpoint(
            method: .post,
            path: "search/history/\(page)",
            body: .json(SearchRequest(query: query)),
            auth: .required
        )
    }

    /// Weekly airing schedule, Monday through Sunday in one payload.
    public static func schedule() -> Endpoint<ScheduleResponse> {
        Endpoint(path: "schedule", auth: .none)
    }
}

/// `discover/*` -- the blocks on the home screen.
public enum DiscoverEndpoints {
    /// Editorial banners and promos.
    public static func interesting() -> Endpoint<PageableResponse<Interesting>> {
        Endpoint(method: .post, path: "discover/interesting", auth: .none)
    }

    /// Releases being talked about today, ranked by comments per day.
    public static func discussing() -> Endpoint<PageableResponse<Release>> {
        Endpoint(method: .post, path: "discover/discussing")
    }

    /// Comments of the week.
    public static func commentsOfTheWeek() -> Endpoint<PageableResponse<ReleaseComment>> {
        Endpoint(method: .post, path: "discover/comments", auth: .none)
    }

    /// "Continue watching" -- requires a session.
    public static func watching(page: Int) -> Endpoint<PageableResponse<Release>> {
        Endpoint(method: .post, path: "discover/watching/\(page)", auth: .required)
    }

    /// Personal recommendations. `previousPage` is sent so the server can avoid
    /// repeating what it just showed.
    public static func recommendations(page: Int, previousPage: Int = 0) -> Endpoint<PageableResponse<Release>> {
        Endpoint(
            method: .post,
            path: "discover/recommendations/\(page)",
            query: ["previous_page": String(previousPage)],
            auth: .required
        )
    }
}
