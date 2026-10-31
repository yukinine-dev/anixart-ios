// Generated from Anixart ChangeLoginResponse (com.swiftsoft.anixartd.network.response.profile.ChangeLoginResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ChangeLoginResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var suggestedLogins: [String]?

    public enum CodingKeys: String, CodingKey {
        case code
        case suggestedLogins = "suggested_logins"
    }
}
