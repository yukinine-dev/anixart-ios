// Generated from Anixart ProfileBadgeSectionsResponse (com.swiftsoft.anixartd.network.response.ProfileBadgeSectionsResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ProfileBadgeSectionsResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var profile: Profile?
    public var recent: [Badge]?
    public var sections: [BadgeSection]?
    public var showcased: [Badge]?
    public var totalCount: Int?

    public enum CodingKeys: String, CodingKey {
        case code
        case profile
        case recent
        case sections
        case showcased
        case totalCount = "total_count"
    }
}
