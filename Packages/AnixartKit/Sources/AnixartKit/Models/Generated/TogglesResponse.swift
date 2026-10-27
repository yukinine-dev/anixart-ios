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

    // Hand-rolled rather than synthesised, so that one mistyped flag
    // costs that flag and not the whole response. See LENIENT in
    // Tools/generate-models.py.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = c.looseInt(.code)
        adBannerBlockId = c.looseString(.adBannerBlockId)
        adBannerDelay = c.looseInt(.adBannerDelay)
        adBannerSizeType = c.looseInt(.adBannerSizeType)
        adInterstitialBlockId = c.looseString(.adInterstitialBlockId)
        adInterstitialDelay = c.looseInt(.adInterstitialDelay)
        baseUrl = c.looseString(.baseUrl)
        codecProfile = c.looseString(.codecProfile)
        consentRequired = c.looseBool(.consentRequired)
        downloadLink = c.looseString(.downloadLink)
        editorUrl = c.looseString(.editorUrl)
        googleAuthAvailable = c.looseBool(.googleAuthAvailable)
        gpDownloadLink = c.looseString(.gpDownloadLink)
        gpWhatsNew = c.looseString(.gpWhatsNew)
        iframeEmbedUrl = c.looseString(.iframeEmbedUrl)
        impMessageBackgroundColor = c.looseString(.impMessageBackgroundColor)
        impMessageEnabled = c.looseBool(.impMessageEnabled)
        impMessageLink = c.looseString(.impMessageLink)
        impMessageText = c.looseString(.impMessageText)
        impMessageTextColor = c.looseString(.impMessageTextColor)
        inAppUpdates = c.looseBool(.inAppUpdates)
        inAppUpdatesFlexibleDelay = c.looseInt(.inAppUpdatesFlexibleDelay)
        inAppUpdatesImmediate = c.looseBool(.inAppUpdatesImmediate)
        kodikAdIframeUrl = c.looseString(.kodikAdIframeUrl)
        kodikIframeAd = c.looseBool(.kodikIframeAd)
        kodikVideoLinksUrl = c.looseString(.kodikVideoLinksUrl)
        lastGPVersionCode = c.looseInt(.lastGPVersionCode)
        lastVersionCode = c.looseInt(.lastVersionCode)
        minBlogCreateRatingScore = c.looseInt(.minBlogCreateRatingScore)
        minGPVersionCode = c.looseInt(.minGPVersionCode)
        minVersionCode = c.looseInt(.minVersionCode)
        overrideGPVersion = c.looseBool(.overrideGPVersion)
        pageNoConnectionUrl = c.looseString(.pageNoConnectionUrl)
        searchBarIconAction = c.looseString(.searchBarIconAction)
        searchBarIconTint = c.looseBool(.searchBarIconTint)
        searchBarIconUrl = c.looseString(.searchBarIconUrl)
        searchBarIconValue = c.looseString(.searchBarIconValue)
        sibnetRandUserAgent = c.looseBool(.sibnetRandUserAgent)
        sibnetUserAgent = c.looseString(.sibnetUserAgent)
        snowfall = c.looseBool(.snowfall)
        sponsorshipAvailable = c.looseBool(.sponsorshipAvailable)
        sponsorshipPromotion = c.looseBool(.sponsorshipPromotion)
        sponsorshipText = c.looseString(.sponsorshipText)
        staticDomain = c.looseString(.staticDomain)
        telegramAuthAvailable = c.looseBool(.telegramAuthAvailable)
        torlookUrl = c.looseString(.torlookUrl)
        vkAuthAvailable = c.looseBool(.vkAuthAvailable)
        whatsNew = c.looseString(.whatsNew)
        yandexAuthAvailable = c.looseBool(.yandexAuthAvailable)
    }
}
