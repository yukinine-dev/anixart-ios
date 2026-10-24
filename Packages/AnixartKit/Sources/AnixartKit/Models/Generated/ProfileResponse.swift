// Generated from Anixart ProfileResponse (com.swiftsoft.anixartd.network.response.profile.ProfileResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ProfileResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var profile: Profile?
    public var isMyProfile: Bool?

    public enum CodingKeys: String, CodingKey {
        case code
        case profile
        case isMyProfile = "is_my_profile"
    }
}
