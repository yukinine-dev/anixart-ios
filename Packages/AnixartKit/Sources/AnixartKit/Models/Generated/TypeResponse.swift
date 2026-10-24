// Generated from Anixart TypeResponse (com.swiftsoft.anixartd.network.response.common.TypeResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct TypeResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var popularTypeIds: [Int]?
    public var types: [EpisodeType]?

    public enum CodingKeys: String, CodingKey {
        case code
        case popularTypeIds = "popular_type_ids"
        case types
    }
}
