import Foundation

/// `release/*`, `related/*`, `type/*` -- a single release and everything hanging off it.
public enum ReleaseEndpoints {
    /// `extendedMode` asks the server to inline related releases, recommendations
    /// and the first page of comments, which is what the Android detail screen uses.
    public static func release(id: Int, extended: Bool = true) -> Endpoint<ReleaseResponse> {
        Endpoint(path: "release/\(id)", query: ["extended_mode": String(extended)])
    }

    public static func random(extended: Bool = false) -> Endpoint<ReleaseResponse> {
        Endpoint(path: "release/random", query: ["extended_mode": String(extended)])
    }

    public static func randomFromFavorites(extended: Bool = false) -> Endpoint<ReleaseResponse> {
        Endpoint(path: "release/random/favorite", query: ["extended_mode": String(extended)], auth: .required)
    }

    public static func randomFromCollection(_ collectionID: Int, extended: Bool = false) -> Endpoint<ReleaseResponse> {
        Endpoint(path: "release/collection/\(collectionID)/random", query: ["extended_mode": String(extended)])
    }

    public static func randomFromList(
        profileID: Int,
        status: ProfileListStatus,
        extended: Bool = false
    ) -> Endpoint<ReleaseResponse> {
        Endpoint(
            path: "release/random/profile/list/\(profileID)/\(status.rawValue)",
            query: ["extended_mode": String(extended)]
        )
    }

    public static func vote(releaseID: Int, score: ReleaseVote) -> Endpoint<StatusResponse> {
        Endpoint(path: "release/vote/add/\(releaseID)/\(score.rawValue)", auth: .required)
    }

    public static func deleteVote(releaseID: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "release/vote/delete/\(releaseID)", auth: .required)
    }

    public static func badges(releaseID: Int, page: Int) -> Endpoint<PageableResponse<Badge>> {
        Endpoint(path: "release/\(releaseID)/badges/\(page)")
    }

    /// Other entries in the same franchise. `relatedID` is `Release.related.id`,
    /// not the release id.
    public static func related(relatedID: Int, page: Int) -> Endpoint<PageableResponse<Release>> {
        Endpoint(path: "related/\(relatedID)/\(page)")
    }

    public static func streamingPlatforms(releaseID: Int) -> Endpoint<PageableResponse<ReleaseStreamingPlatform>> {
        Endpoint(path: "release/streaming/platform/\(releaseID)", auth: .none)
    }

    // MARK: - Voice-over types (`type/*`)

    /// All voice-over studios known to the app, used to populate the catalogue filter.
    public static func allTypes() -> Endpoint<TypeResponse> {
        Endpoint(path: "type/all")
    }

    public static func pinType(releaseID: Int, typeID: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "type/pin/\(releaseID)/\(typeID)", auth: .required)
    }

    public static func unpinType(releaseID: Int, typeID: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "type/unpin/\(releaseID)/\(typeID)", auth: .required)
    }
}
