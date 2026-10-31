import Foundation

/// `collection/*` and `collectionFavorite/*`.
public enum CollectionEndpoints {
    public static func collection(id: Int) -> Endpoint<CollectionResponse> {
        Endpoint(path: "collection/\(id)")
    }

    public static func releases(collectionID: Int, page: Int) -> Endpoint<PageableResponse<Release>> {
        Endpoint(path: "collection/\(collectionID)/releases/\(page)")
    }

    /// The public collections feed. `where` selects the section (0 is "all") and
    /// `previousPage` lets the server keep its shuffle stable across pages.
    public static func all(
        page: Int,
        previousPage: Int = 0,
        where section: Int = 0,
        sort: Int = 0
    ) -> Endpoint<PageableResponse<ReleaseCollection>> {
        Endpoint(
            path: "collection/all/\(page)",
            query: [
                "previous_page": String(previousPage),
                "where": String(section),
                "sort": String(sort)
            ]
        )
    }

    public static func byProfile(_ profileID: Int, page: Int) -> Endpoint<PageableResponse<ReleaseCollection>> {
        Endpoint(path: "collection/all/profile/\(profileID)/\(page)")
    }

    /// Collections a given release appears in.
    public static func containing(releaseID: Int, page: Int, sort: Int = 0) -> Endpoint<PageableResponse<ReleaseCollection>> {
        Endpoint(path: "collection/all/release/\(releaseID)/\(page)", query: ["sort": String(sort)])
    }

    public static func favorites(page: Int) -> Endpoint<PageableResponse<ReleaseCollection>> {
        Endpoint(path: "collectionFavorite/all/\(page)", auth: .required)
    }

    public static func addFavorite(collectionID: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "collectionFavorite/add/\(collectionID)", auth: .required)
    }

    public static func removeFavorite(collectionID: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "collectionFavorite/delete/\(collectionID)", auth: .required)
    }

    /// The APK's ReleaseAddCollectionResponse has only Response's status code.
    /// This mutation is a GET with `release_id`, not a JSON POST.
    public static func addRelease(collectionID: Int, releaseID: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "collectionMy/release/add/\(collectionID)",
                 query: ["release_id": String(releaseID)], auth: .required)
    }
}
