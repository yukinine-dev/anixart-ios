// Generated from Anixart ProfileSelectThemeResponse (com.swiftsoft.anixartd.network.response.preferences.ProfileSelectThemeResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ProfileSelectThemeResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var theme: ProfileTheme?

    public enum CodingKeys: String, CodingKey {
        case code
        case theme
    }
}
