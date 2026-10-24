// Generated from Anixart EpisodeUpdate (com.swiftsoft.anixartd.database.entity.episode.EpisodeUpdate).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct EpisodeUpdate: Codable, Hashable, Sendable {
    public var lastEpisodeSourceUpdateId: Int?
    public var lastEpisodeSourceUpdateName: String?
    public var lastEpisodeTypeUpdateId: Int?
    public var lastEpisodeTypeUpdateName: String?
    public var lastEpisodeUpdateDate: Int?
    public var lastEpisodeUpdateName: String?

    public enum CodingKeys: String, CodingKey {
        case lastEpisodeSourceUpdateId = "last_episode_source_update_id"
        case lastEpisodeSourceUpdateName = "last_episode_source_update_name"
        case lastEpisodeTypeUpdateId = "last_episode_type_update_id"
        case lastEpisodeTypeUpdateName
        case lastEpisodeUpdateDate = "last_episode_update_date"
        case lastEpisodeUpdateName = "last_episode_update_name"
    }
}
