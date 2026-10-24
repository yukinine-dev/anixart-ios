// Generated from Anixart ConfigUrlsResponse (com.swiftsoft.anixartd.network.response.config.ConfigUrlsResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ConfigUrlsResponse: Codable, Hashable, Sendable {
    public var apiUrls: [String]?
    public var consentRequired: Bool?
    public var editorUrl: String?
    public var googleAuthAvailable: Bool?
    public var shouldUseMirrorUrls: Bool?
    public var staticDomain: String?
    public var telegramAuthAvailable: Bool?
    public var vkAuthAvailable: Bool?
    public var yandexAuthAvailable: Bool?

    public enum CodingKeys: String, CodingKey {
        case apiUrls
        case consentRequired
        case editorUrl
        case googleAuthAvailable
        case shouldUseMirrorUrls
        case staticDomain
        case telegramAuthAvailable
        case vkAuthAvailable
        case yandexAuthAvailable
    }
}
