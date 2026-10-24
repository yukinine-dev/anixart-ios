// Generated from Anixart ReleaseSearchResponse (com.swiftsoft.anixartd.network.response.search.ReleaseSearchResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ReleaseSearchResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var related: Related?
    public var releases: [Release]?

    public enum CodingKeys: String, CodingKey {
        case code
        case related
        case releases
    }
}
