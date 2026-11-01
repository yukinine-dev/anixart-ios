import Foundation

extension Profile {
    /// Profile activity timestamps use Unix seconds, like registration/history.
    public var lastActivityDate: Date? {
        guard let lastActivityTime, lastActivityTime > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(lastActivityTime))
    }

    /// Public profiles carry flat theme settings, not a nested `theme` object.
    /// The profile ID is only a stable rendering seed, never a theme-selection ID.
    public var showcaseTheme: ProfileTheme {
        ProfileTheme(
            id: id,
            themeAnimationEnabled: themeAnimationEnabled,
            themeAnimationSpeed: themeAnimationSpeed,
            themeBackgroundAlpha: themeBackgroundAlpha,
            themeBackgroundMode: themeBackgroundMode,
            themeBackgroundUrl: themeBackgroundUrl,
            themeEnabled: themeEnabled,
            themeGradientAngle: themeGradientAngle,
            themeGradientEndColor: themeGradientEndColor,
            themeGradientStartColor: themeGradientStartColor,
            themeIconAlpha: themeIconAlpha,
            themeIconColor: themeIconColor,
            themeIconDensity: themeIconDensity,
            themeIconResName: themeIconResName,
            themeIconSize: themeIconSize,
            themeIconUrl: themeIconUrl
        )
    }
}
