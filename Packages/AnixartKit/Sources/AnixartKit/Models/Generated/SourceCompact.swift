// Generated from Anixart SourceCompact (com.swiftsoft.anixartd.database.entity.episode.source.SourceCompact).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct SourceCompact: Codable, Hashable, Sendable {
    public var name: String?
    public var type: TypeCompact?

    public enum CodingKeys: String, CodingKey {
        case name
        case type
    }
}
