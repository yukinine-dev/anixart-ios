// Generated from Anixart Type (com.swiftsoft.anixartd.database.entity.episode.type.Type).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct EpisodeType: Codable, Hashable, Sendable, Identifiable {
    public var episodesCount: Int?
    public var icon: String?
    public var id: Int?
    public var name: String?
    public var pinned: Bool?
    public var quality: Int?
    public var viewCount: Int?
    public var workers: String?
    public var isSub: Bool?

    public enum CodingKeys: String, CodingKey {
        case episodesCount = "episodes_count"
        case icon
        case id
        case name
        case pinned
        case quality
        case viewCount = "view_count"
        case workers
        case isSub = "is_sub"
    }
}
