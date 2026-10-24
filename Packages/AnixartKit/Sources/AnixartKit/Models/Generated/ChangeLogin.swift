// Generated from Anixart ChangeLogin (com.swiftsoft.anixartd.database.entity.profile.ChangeLogin).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ChangeLogin: Codable, Hashable, Sendable, Identifiable {
    public var id: Int?
    public var newLogin: String?
    public var timestamp: Int?

    public enum CodingKeys: String, CodingKey {
        case id
        case newLogin
        case timestamp
    }
}
