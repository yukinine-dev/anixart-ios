// Generated from Anixart ProfileSlim (com.swiftsoft.anixartd.database.entity.profile.ProfileSlim).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ProfileSlim: Codable, Hashable, Sendable, Identifiable {
    public var avatar: String?
    public var id: Int
    public var login: String?

    public enum CodingKeys: String, CodingKey {
        case avatar
        case id
        case login
    }
}
