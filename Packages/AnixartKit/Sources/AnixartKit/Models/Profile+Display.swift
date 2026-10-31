import Foundation

extension Profile {
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
