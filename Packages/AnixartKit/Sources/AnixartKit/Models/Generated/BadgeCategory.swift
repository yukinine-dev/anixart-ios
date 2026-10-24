// Generated from Anixart BadgeCategory (com.swiftsoft.anixartd.database.entity.profile.BadgeCategory).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct BadgeCategory: Codable, Hashable, Sendable, Identifiable {
    public var id: Int?
    public var title: String?

    public enum CodingKeys: String, CodingKey {
        case id
        case title
    }
}
