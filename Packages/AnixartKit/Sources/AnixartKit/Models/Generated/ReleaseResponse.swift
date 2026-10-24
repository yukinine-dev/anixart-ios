// Generated from Anixart ReleaseResponse (com.swiftsoft.anixartd.network.response.release.ReleaseResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ReleaseResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var release: Release?

    public enum CodingKeys: String, CodingKey {
        case code
        case release
    }
}
