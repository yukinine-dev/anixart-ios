// Generated from Anixart LastWatchedEpisode (com.swiftsoft.anixartd.database.entity.episode.LastWatchedEpisode).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct LastWatchedEpisode: Codable, Hashable, Sendable, Identifiable {
    public var episodeId: Int?
    public var id: Int
    public var releaseId: Int?
    public var sourceId: Int?
    public var timestamp: Int?
    public var typeId: Int?

    public enum CodingKeys: String, CodingKey {
        case episodeId
        case id
        case releaseId
        case sourceId
        case timestamp
        case typeId
    }
}
