// Generated from Anixart ProfileCompact (com.swiftsoft.anixartd.database.entity.profile.ProfileCompact).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ProfileCompact: Codable, Hashable, Sendable, Identifiable {
    public var avatar: String?
    public var badgeId: Int?
    public var badgeName: String?
    public var badgeType: Int?
    public var badgeUrl: String?
    public var banExpires: Int?
    public var banReason: String?
    public var id: Int
    public var login: String?
    public var privilegeLevel: Int?
    public var isBanned: Bool?
    public var isSponsor: Bool?
    public var isVerified: Bool?

    public enum CodingKeys: String, CodingKey {
        case avatar
        case badgeId
        case badgeName
        case badgeType
        case badgeUrl
        case banExpires = "ban_expires"
        case banReason = "ban_reason"
        case id
        case login
        case privilegeLevel = "privilege_level"
        case isBanned = "is_banned"
        case isSponsor = "is_sponsor"
        case isVerified = "is_verified"
    }
}
