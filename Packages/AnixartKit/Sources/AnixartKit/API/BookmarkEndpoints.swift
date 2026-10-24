import Foundation

/// `favorite/*`, `profile/list/*`, `history/*` -- the Bookmarks tab.
///
/// Anixart keeps two independent things here: the five mutually exclusive watch
/// lists (`profile/list`) and a separate favourites flag (`favorite`), so a release
/// can sit in "Watching" and be favourited at the same time.
public enum BookmarkEndpoints {
    // MARK: - Watch lists

    public static func list(
        _ status: ProfileListStatus,
        page: Int,
        sort: BookmarkSort = .addedDescending,
        hideAnnounces: Bool = false
    ) -> Endpoint<PageableResponse<Release>> {
        Endpoint(
            path: "profile/list/all/\(status.rawValue)/\(page)",
            query: [
                "sort": String(sort.rawValue),
                "filter_announce": hideAnnounces ? "1" : nil
            ],
            auth: .required
        )
    }

    /// Another user's public list.
    public static func list(
        of profileID: Int,
        status: ProfileListStatus,
        page: Int,
        sort: BookmarkSort = .addedDescending
    ) -> Endpoint<PageableResponse<Release>> {
        Endpoint(
            path: "profile/list/all/\(profileID)/\(status.rawValue)/\(page)",
            query: ["sort": String(sort.rawValue)]
        )
    }

    /// Moving a release between lists is an add to the target list; the server
    /// removes it from whichever list it was in.
    public static func addToList(releaseID: Int, status: ProfileListStatus) -> Endpoint<StatusResponse> {
        Endpoint(path: "profile/list/add/\(status.rawValue)/\(releaseID)", auth: .required)
    }

    public static func removeFromList(releaseID: Int, status: ProfileListStatus) -> Endpoint<StatusResponse> {
        Endpoint(path: "profile/list/delete/\(status.rawValue)/\(releaseID)", auth: .required)
    }

    // MARK: - Favourites

    public static func favorites(
        page: Int,
        sort: BookmarkSort = .addedDescending,
        hideAnnounces: Bool = false
    ) -> Endpoint<PageableResponse<Release>> {
        Endpoint(
            path: "favorite/all/\(page)",
            query: [
                "sort": String(sort.rawValue),
                "filter_announce": hideAnnounces ? "1" : nil
            ],
            auth: .required
        )
    }

    public static func addFavorite(releaseID: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "favorite/add/\(releaseID)", auth: .required)
    }

    public static func removeFavorite(releaseID: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "favorite/delete/\(releaseID)", auth: .required)
    }

    // MARK: - Watch history

    public static func history(page: Int) -> Endpoint<PageableResponse<Release>> {
        Endpoint(path: "history/\(page)", auth: .required)
    }

    public static func removeFromHistory(releaseID: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "history/delete/\(releaseID)", auth: .required)
    }
}
