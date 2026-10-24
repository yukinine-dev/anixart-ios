import Foundation

/// `episode/*`.
///
/// Playback is a three-level drill-down, and all three levels are separate calls:
/// voice-over type -> hosting source -> episode list.
public enum EpisodeEndpoints {
    /// Level 1: voice-over types available for a release.
    public static func types(releaseID: Int) -> Endpoint<TypesResponse> {
        Endpoint(path: "episode/\(releaseID)")
    }

    /// Level 2: hosting sources (Kodik, Sibnet, ...) carrying a given voice-over.
    public static func sources(releaseID: Int, typeID: Int) -> Endpoint<SourcesResponse> {
        Endpoint(path: "episode/\(releaseID)/\(typeID)", auth: .none)
    }

    /// Level 3: the episode list itself. `sort` is `0` for ascending order.
    public static func episodes(
        releaseID: Int,
        typeID: Int,
        sourceID: Int,
        sort: Int = 0
    ) -> Endpoint<EpisodeResponse> {
        Endpoint(
            path: "episode/\(releaseID)/\(typeID)/\(sourceID)",
            query: ["sort": String(sort)]
        )
    }

    /// Marks one episode watched. Drives both the per-episode checkmark and the
    /// release's "last viewed" state.
    public static func markWatched(releaseID: Int, sourceID: Int, position: Int) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "episode/watch/\(releaseID)/\(sourceID)/\(position)", auth: .required)
    }

    /// Marks every episode of a source watched.
    public static func markAllWatched(releaseID: Int, sourceID: Int) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "episode/watch/\(releaseID)/\(sourceID)", auth: .required)
    }

    public static func markUnwatched(releaseID: Int, sourceID: Int, position: Int) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "episode/unwatch/\(releaseID)/\(sourceID)/\(position)", auth: .required)
    }

    public static func markAllUnwatched(releaseID: Int, sourceID: Int) -> Endpoint<StatusResponse> {
        Endpoint(method: .post, path: "episode/unwatch/\(releaseID)/\(sourceID)", auth: .required)
    }

    public static func updates(releaseID: Int, page: Int) -> Endpoint<PageableResponse<EpisodeUpdate>> {
        Endpoint(path: "episode/updates/\(releaseID)/\(page)", auth: .none)
    }

    /// Records playback progress so "continue watching" survives a reinstall.
    public static func saveProgress(releaseID: Int, sourceID: Int, position: Int) -> Endpoint<StatusResponse> {
        Endpoint(path: "history/add/\(releaseID)/\(sourceID)/\(position)", auth: .required)
    }
}
