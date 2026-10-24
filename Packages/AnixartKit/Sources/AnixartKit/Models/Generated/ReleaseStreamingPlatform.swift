// Generated from Anixart ReleaseStreamingPlatform (com.swiftsoft.anixartd.database.entity.release.ReleaseStreamingPlatform).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ReleaseStreamingPlatform: Codable, Hashable, Sendable, Identifiable {
    public var icon: String?
    public var id: Int?
    public var name: String?
    public var url: String?

    public enum CodingKeys: String, CodingKey {
        case icon
        case id
        case name
        case url
    }
}
