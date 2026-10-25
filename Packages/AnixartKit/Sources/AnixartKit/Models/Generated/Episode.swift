// Generated from Anixart Episode (com.swiftsoft.anixartd.database.entity.episode.Episode).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct Episode: Codable, Hashable, Sendable {
    public var addedDate: Int?
    public var iframe: Bool?
    public var name: String?
    public var playbackPosition: Int?
    public var position: Int?
    public var quality: Int?
    public var releaseId: Int?
    public var sourceId: Int?
    public var url: String?
    public var isFiller: Bool?
    public var isWatched: Bool?

    public enum CodingKeys: String, CodingKey {
        case addedDate
        case iframe
        case name
        case playbackPosition
        case position
        case quality
        case releaseId
        case sourceId
        case url
        case isFiller = "is_filler"
        case isWatched = "is_watched"
    }
}
