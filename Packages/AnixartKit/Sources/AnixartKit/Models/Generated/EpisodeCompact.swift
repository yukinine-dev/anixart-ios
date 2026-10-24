// Generated from Anixart EpisodeCompact (com.swiftsoft.anixartd.database.entity.episode.EpisodeCompact).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct EpisodeCompact: Codable, Hashable, Sendable {
    public var name: String?
    public var release: ReleaseCompact?
    public var source: SourceCompact?

    public enum CodingKeys: String, CodingKey {
        case name
        case release
        case source
    }
}
