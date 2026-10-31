// Generated from Anixart ProfileHealthStatusResponse (com.swiftsoft.anixartd.network.response.profile.enforcement.ProfileHealthStatusResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ProfileHealthStatusResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var banCount: Int?
    public var banFor3MonthCount: Int?
    public var blogMuteExpires: Int?
    public var blogSuspensionExpires: Int?
    public var lastBanExpires: Int?
    public var lastBanTimestamp: Int?

    public enum CodingKeys: String, CodingKey {
        case code
        case banCount = "ban_count"
        case banFor3MonthCount = "ban_for_3_month_count"
        case blogMuteExpires = "blog_mute_expires"
        case blogSuspensionExpires = "blog_suspension_expires"
        case lastBanExpires = "last_ban_expires"
        case lastBanTimestamp = "last_ban_timestamp"
    }
}
