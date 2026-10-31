// Generated from Anixart ChangeLoginInfoResponse (com.swiftsoft.anixartd.network.response.profile.ChangeLoginInfoResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ChangeLoginInfoResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var avatar: String?
    public var lastChangeAt: Int?
    public var login: String?
    public var nextChangeAvailableAt: Int?
    public var isChangeAvailable: Bool?

    public enum CodingKeys: String, CodingKey {
        case code
        case avatar
        case lastChangeAt = "last_change_at"
        case login
        case nextChangeAvailableAt = "next_change_available_at"
        case isChangeAvailable = "is_change_available"
    }
}
