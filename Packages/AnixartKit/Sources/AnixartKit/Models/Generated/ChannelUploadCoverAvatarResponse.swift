// Generated from Anixart ChannelUploadCoverAvatarResponse (com.swiftsoft.anixartd.network.response.channels.ChannelUploadCoverAvatarResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ChannelUploadCoverAvatarResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var url: String?

    public enum CodingKeys: String, CodingKey {
        case code
        case url
    }
}
