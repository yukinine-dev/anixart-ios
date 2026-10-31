// Generated from Anixart ProfileEnforcementResponse (com.swiftsoft.anixartd.network.response.profile.enforcement.ProfileEnforcementResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ProfileEnforcementResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var enforcement: ProfileEnforcement?

    public enum CodingKeys: String, CodingKey {
        case code
        case enforcement
    }
}
