// Generated from Anixart Badge (com.swiftsoft.anixartd.database.entity.profile.Badge).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct Badge: Codable, Hashable, Sendable, Identifiable {
    public var award: BadgeAward?
    public var badgeUrl: String?
    public var category: BadgeCategory?
    public var description: String?
    public var id: Int
    public var imageMediumUrl: String?
    public var imageSmallUrl: String?
    public var name: String?
    public var ownershipPercentage: Double?
    public var rarity: String?
    public var timestamp: Int?
    public var type: Int?
    public var isAvailable: Bool?
    public var isOwned: Bool?
    public var isSelected: Bool?
    public var isShowcased: Bool?

    public enum CodingKeys: String, CodingKey {
        case award
        case badgeUrl = "image_url"
        case category
        case description
        case id
        case imageMediumUrl = "image_medium_url"
        case imageSmallUrl = "image_small_url"
        case name
        case ownershipPercentage = "ownership_percentage"
        case rarity
        case timestamp
        case type
        case isAvailable = "is_available"
        case isOwned = "is_owned"
        case isSelected = "is_selected"
        case isShowcased = "is_showcased"
    }
}
