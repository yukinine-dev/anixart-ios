// Generated from Anixart ChangeEmailResponse (com.swiftsoft.anixartd.network.response.profile.ChangeEmailResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ChangeEmailResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var hash: String?
    public var timestampExpires: Int?

    public enum CodingKeys: String, CodingKey {
        case code
        case hash
        case timestampExpires = "timestamp_expires"
    }
}
