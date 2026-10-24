// Generated from Anixart RoleDto (com.swiftsoft.anixartd.database.entity.profile.RoleDto).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct RoleDto: Codable, Hashable, Sendable, Identifiable {
    public var color: String?
    public var id: Int
    public var name: String?

    public enum CodingKeys: String, CodingKey {
        case color
        case id
        case name
    }
}
