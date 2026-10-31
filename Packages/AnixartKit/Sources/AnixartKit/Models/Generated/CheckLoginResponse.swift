// Generated from Anixart CheckLoginResponse (com.swiftsoft.anixartd.network.response.auth.CheckLoginResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct CheckLoginResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var available: Bool?
    public var suggestedLogins: [String]?

    public enum CodingKeys: String, CodingKey {
        case code
        case available
        case suggestedLogins = "suggested_logins"
    }
}
