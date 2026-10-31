// Generated from Anixart BadgeSection (com.swiftsoft.anixartd.database.entity.profile.BadgeSection).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct BadgeSection: Codable, Hashable, Sendable, Identifiable {
    public var content: [Badge]?
    public var count: Int?
    public var id: Int
    public var title: String?

    public enum CodingKeys: String, CodingKey {
        case content
        case count
        case id
        case title
    }
}
