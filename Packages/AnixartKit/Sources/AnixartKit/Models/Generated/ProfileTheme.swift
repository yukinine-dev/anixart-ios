// Generated from Anixart Theme (com.swiftsoft.anixartd.database.entity.profile.Theme).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ProfileTheme: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String?
    public var themeAnimationEnabled: Bool?
    public var themeAnimationSpeed: String?
    public var themeBackgroundAlpha: Double?
    public var themeBackgroundMode: String?
    public var themeBackgroundUrl: String?
    public var themeEnabled: Bool?
    public var themeGradientAngle: String?
    public var themeGradientEndColor: String?
    public var themeGradientStartColor: String?
    public var themeIconAlpha: Double?
    public var themeIconColor: String?
    public var themeIconDensity: String?
    public var themeIconResName: String?
    public var themeIconSize: String?
    public var themeIconUrl: String?

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case themeAnimationEnabled = "theme_animation_enabled"
        case themeAnimationSpeed = "theme_animation_speed"
        case themeBackgroundAlpha = "theme_background_alpha"
        case themeBackgroundMode = "theme_background_mode"
        case themeBackgroundUrl = "theme_background_url"
        case themeEnabled = "theme_enabled"
        case themeGradientAngle = "theme_gradient_angle"
        case themeGradientEndColor = "theme_gradient_end_color"
        case themeGradientStartColor = "theme_gradient_start_color"
        case themeIconAlpha = "theme_icon_alpha"
        case themeIconColor = "theme_icon_color"
        case themeIconDensity = "theme_icon_density"
        case themeIconResName = "theme_icon_res_name"
        case themeIconSize = "theme_icon_size"
        case themeIconUrl = "theme_icon_url"
    }
}
