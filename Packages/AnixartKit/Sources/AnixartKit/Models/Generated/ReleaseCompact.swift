// Generated from Anixart ReleaseCompact (com.swiftsoft.anixartd.database.entity.release.ReleaseCompact).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ReleaseCompact: Codable, Hashable, Sendable, Identifiable {
    public var id: Int?
    public var image: String?
    public var titleRu: String?

    public enum CodingKeys: String, CodingKey {
        case id
        case image
        case titleRu = "title_ru"
    }
}
