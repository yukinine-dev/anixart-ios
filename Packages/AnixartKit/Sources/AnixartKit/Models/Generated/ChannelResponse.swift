// Generated from Anixart ChannelResponse (com.swiftsoft.anixartd.network.response.channels.ChannelResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ChannelResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var channel: Channel?
    public var suggestionCount: Int?

    public enum CodingKeys: String, CodingKey {
        case code
        case channel
        case suggestionCount = "suggestion_count"
    }
}
