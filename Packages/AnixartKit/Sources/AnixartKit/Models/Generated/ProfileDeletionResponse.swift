// Generated from Anixart ProfileDeletionResponse (com.swiftsoft.anixartd.network.response.profile.ProfileDeletionResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ProfileDeletionResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var deleteAt: Int?
    public var requestedAt: Int?

    public enum CodingKeys: String, CodingKey {
        case code
        case deleteAt = "delete_at"
        case requestedAt = "requested_at"
    }
}
