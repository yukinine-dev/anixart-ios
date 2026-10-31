// Generated from Anixart ChangeEmailResendResponse (com.swiftsoft.anixartd.network.response.profile.ChangeEmailResendResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ChangeEmailResendResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var timestampExpires: Int?

    public enum CodingKeys: String, CodingKey {
        case code
        case timestampExpires = "timestamp_expires"
    }
}
