// Generated from Anixart RestoreVerifyResponse (com.swiftsoft.anixartd.network.response.auth.RestoreVerifyResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct RestoreVerifyResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var attemptsLeft: Int?
    public var profile: Profile?
    public var profileToken: ProfileToken?

    public enum CodingKeys: String, CodingKey {
        case code
        case attemptsLeft = "attempts_left"
        case profile
        case profileToken
    }
}
