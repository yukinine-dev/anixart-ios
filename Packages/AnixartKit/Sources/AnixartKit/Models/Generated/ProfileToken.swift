// Generated from Anixart ProfileToken (com.swiftsoft.anixartd.database.entity.profile.ProfileToken).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ProfileToken: Codable, Hashable, Sendable, Identifiable {
    public var id: Int?
    public var token: String?

    public enum CodingKeys: String, CodingKey {
        case id
        case token
    }
}
