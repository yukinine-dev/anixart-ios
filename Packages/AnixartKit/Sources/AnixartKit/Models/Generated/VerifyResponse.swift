// Generated from Anixart VerifyResponse (com.swiftsoft.anixartd.network.response.auth.VerifyResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct VerifyResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var profile: Profile?
    public var profileToken: ProfileToken?
    public var suggestedLogins: [String]?

    public enum CodingKeys: String, CodingKey {
        case code
        case profile
        case profileToken
        case suggestedLogins = "suggested_logins"
    }
}
