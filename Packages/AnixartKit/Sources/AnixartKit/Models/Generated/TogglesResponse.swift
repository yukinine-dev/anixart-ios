// Generated from Anixart TogglesResponse (com.swiftsoft.anixartd.network.response.config.TogglesResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct TogglesResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var adBannerBlockId: String?
    public var adBannerDelay: Int?
    public var adBannerSizeType: Int?
    public var adInterstitialBlockId: String?
    public var adInterstitialDelay: Int?
    public var baseUrl: String?
    public var codecProfile: String?
    public var consentRequired: Bool?
    public var downloadLink: String?
    public var editorUrl: String?
    public var googleAuthAvailable: Bool?
    public var gpDownloadLink: String?
    public var gpWhatsNew: String?
    public var iframeEmbedUrl: String?
    public var impMessageBackgroundColor: String?
    public var impMessageEnabled: Bool?
    public var impMessageLink: String?
    public var impMessageText: String?
    public var impMessageTextColor: String?
    public var inAppUpdates: Bool?
    public var inAppUpdatesFlexibleDelay: Int?
    public var inAppUpdatesImmediate: Bool?
    public var kodikAdIframeUrl: String?
    public var kodikIframeAd: Bool?
    public var kodikVideoLinksUrl: String?
    public var lastGPVersionCode: Int?
    public var lastVersionCode: Int?
    public var minBlogCreateRatingScore: Int?
    public var minGPVersionCode: Int?
    public var minVersionCode: Int?
    public var overrideGPVersion: Bool?
    public var pageNoConnectionUrl: String?
    public var searchBarIconAction: String?
    public var searchBarIconTint: Bool?
    public var searchBarIconUrl: String?
    public var searchBarIconValue: String?
    public var sibnetRandUserAgent: Bool?
    public var sibnetUserAgent: String?
    public var snowfall: Bool?
    public var sponsorshipAvailable: Bool?
    public var sponsorshipPromotion: Bool?
    public var sponsorshipText: String?
    public var staticDomain: String?
    public var telegramAuthAvailable: Bool?
    public var torlookUrl: String?
    public var vkAuthAvailable: Bool?
    public var whatsNew: String?
    public var yandexAuthAvailable: Bool?

    public enum CodingKeys: String, CodingKey {
        case code
        case adBannerBlockId
        case adBannerDelay
        case adBannerSizeType
        case adInterstitialBlockId
        case adInterstitialDelay
        case baseUrl
        case codecProfile
        case consentRequired
        case downloadLink
        case editorUrl
        case googleAuthAvailable
        case gpDownloadLink
        case gpWhatsNew
        case iframeEmbedUrl
        case impMessageBackgroundColor
        case impMessageEnabled
        case impMessageLink
        case impMessageText
        case impMessageTextColor
        case inAppUpdates
        case inAppUpdatesFlexibleDelay
        case inAppUpdatesImmediate
        case kodikAdIframeUrl
        case kodikIframeAd
        case kodikVideoLinksUrl
        case lastGPVersionCode
        case lastVersionCode
        case minBlogCreateRatingScore
        case minGPVersionCode
        case minVersionCode
        case overrideGPVersion
        case pageNoConnectionUrl
        case searchBarIconAction
        case searchBarIconTint
        case searchBarIconUrl
        case searchBarIconValue
        case sibnetRandUserAgent
        case sibnetUserAgent
        case snowfall
        case sponsorshipAvailable
        case sponsorshipPromotion
        case sponsorshipText
        case staticDomain
        case telegramAuthAvailable
        case torlookUrl
        case vkAuthAvailable
        case whatsNew
        case yandexAuthAvailable
    }
}
