// Generated from Anixart Source (com.swiftsoft.anixartd.database.entity.episode.source.Source).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct EpisodeSource: Codable, Hashable, Sendable, Identifiable {
    public var episodesCount: Int?
    public var id: Int
    public var name: String?
    public var quality: Int?
    public var type: Embedded<EpisodeType>?

    public enum CodingKeys: String, CodingKey {
        case episodesCount = "episodes_count"
        case id
        case name
        case quality
        case type
    }
}
