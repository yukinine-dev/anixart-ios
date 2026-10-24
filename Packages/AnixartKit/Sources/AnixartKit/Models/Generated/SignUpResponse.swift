// Generated from Anixart SignUpResponse (com.swiftsoft.anixartd.network.response.auth.SignUpResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct SignUpResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var codeLength: Int?
    public var codeTimeLeft: Int?
    public var codeTimestampExpires: Int?
    public var hash: String?
    public var suggestedLogins: [String]?

    public enum CodingKeys: String, CodingKey {
        case code
        case codeLength = "code_length"
        case codeTimeLeft = "code_time_left"
        case codeTimestampExpires
        case hash
        case suggestedLogins = "suggested_logins"
    }
}
