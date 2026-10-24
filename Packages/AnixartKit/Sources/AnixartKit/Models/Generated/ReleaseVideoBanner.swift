// Generated from Anixart ReleaseVideoBanner (com.swiftsoft.anixartd.database.entity.release.video.ReleaseVideoBanner).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ReleaseVideoBanner: Codable, Hashable, Sendable {
    public var actionId: Int?
    public var image: String?
    public var name: String?
    public var value: String?
    public var isNew: Bool?

    public enum CodingKeys: String, CodingKey {
        case actionId = "action_id"
        case image
        case name
        case value
        case isNew = "is_new"
    }
}
