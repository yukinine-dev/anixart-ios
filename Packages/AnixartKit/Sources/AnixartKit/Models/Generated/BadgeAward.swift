// Generated from Anixart BadgeAward (com.swiftsoft.anixartd.database.entity.profile.BadgeAward).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct BadgeAward: Codable, Hashable, Sendable {
    public var episodeName: String?
    public var profileListStatus: Int?
    public var releaseId: Int?
    public var releaseImage: String?
    public var releaseTitle: String?
    public var trigger: String?

    public enum CodingKeys: String, CodingKey {
        case episodeName = "episode_name"
        case profileListStatus = "profile_list_status"
        case releaseId = "release_id"
        case releaseImage = "release_image"
        case releaseTitle = "release_title"
        case trigger
    }
}
