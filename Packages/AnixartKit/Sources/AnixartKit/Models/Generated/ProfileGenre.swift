// Generated from Anixart ProfileGenre (com.swiftsoft.anixartd.database.entity.profile.ProfileGenre).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ProfileGenre: Codable, Hashable, Sendable {
    public var name: String?
    public var percentage: Int?

    public enum CodingKeys: String, CodingKey {
        case name
        case percentage
    }
}
