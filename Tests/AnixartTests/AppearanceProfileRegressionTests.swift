import Foundation
import SwiftUI
import UIKit
import XCTest
import AnixartKit
@testable import Anixart

final class AppearanceProfileRegressionTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let suite = "AppearanceProfileRegressionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testAbsentInvalidThemeAndAccentUseOriginalWithoutWriting() throws {
        let storage = try defaults()
        XCTAssertEqual(AppVisualTheme.stored(nil), .original)
        XCTAssertEqual(AppVisualTheme.stored("unknown"), .original)
        XCTAssertEqual(AppAccentChoice.stored(nil), .anixart)
        XCTAssertEqual(AppThemePalette.current(dark: false, defaults: storage), AppThemePalette.make(theme: .original, accent: .anixart, dark: false))
        XCTAssertNil(storage.object(forKey: DeviceAppearancePreferenceKey.visualTheme))
        XCTAssertNil(storage.object(forKey: DeviceAppearancePreferenceKey.accent))
        XCTAssertEqual(AppVisualTheme.allCases, [.original, .accented, .oled, .monet])
    }

    func testOLEDBlackIsIndependentOfLightPreferenceAndOtherThemesRestoreIt() {
        let palette = AppThemePalette.make(theme: .oled, accent: .anixart, dark: false)
        XCTAssertEqual(palette.background, ThemeRGB(0x000000))
        XCTAssertNotEqual(palette.surface, palette.background)
        XCTAssertEqual(AppVisualTheme.oled.colorScheme(normal: .light), .dark)
        XCTAssertEqual(AppVisualTheme.original.colorScheme(normal: .light), .light)
        XCTAssertNil(AppVisualTheme.original.colorScheme(normal: nil))
    }

    func testEveryPaletteHasReadableTextAndBoundedColourComponents() {
        for theme in AppVisualTheme.allCases {
            for accent in AppAccentChoice.allCases {
                for dark in [false, true] {
                    let palette = AppThemePalette.make(theme: theme, accent: accent, dark: dark)
                    for colour in [palette.background, palette.surface, palette.raisedSurface, palette.text, palette.secondaryText, palette.accent] {
                        for value in [colour.red, colour.green, colour.blue] { XCTAssertTrue(value.isFinite && (0...1).contains(value)) }
                    }
                    XCTAssertGreaterThanOrEqual(palette.text.contrast(with: palette.background), 4.5, "\(theme) \(accent) \(dark)")
                    XCTAssertGreaterThanOrEqual(palette.text.contrast(with: palette.surface), 4.5, "\(theme) \(accent) \(dark)")
                    XCTAssertGreaterThanOrEqual(palette.secondaryText.contrast(with: palette.surface), 4.5,
                                                "Badge contrast: \(theme) \(accent) \(dark)")
                }
            }
        }
    }

    func testAccentedDefaultUsesCarmineButAnExplicitLavenderIsNotOverwritten() {
        let implicit = AppThemePalette.make(theme: .accented, accent: .anixart, dark: false)
        let explicit = AppThemePalette.make(theme: .accented, accent: .lavender, dark: false)
        XCTAssertNotEqual(implicit.accent, explicit.accent)
        XCTAssertGreaterThan(implicit.accent.red, implicit.accent.blue)
        XCTAssertGreaterThan(explicit.accent.blue, explicit.accent.red)
        XCTAssertNotEqual(implicit.surface, AppThemePalette.make(theme: .original, accent: .anixart, dark: false).surface)
    }

    @MainActor
    func testThemeUpdatesPreserveNavigationAndSwiftUIOwnedContentBackgrounds() {
        let screen = UIViewController()
        let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        collection.backgroundColor = .magenta
        screen.view.addSubview(collection)
        let navigation = UINavigationController(rootViewController: screen)
        let tabs = UITabBarController()
        tabs.viewControllers = [navigation]
        tabs.loadViewIfNeeded()
        navigation.loadViewIfNeeded()
        let originalView = screen.view
        for theme in AppVisualTheme.allCases {
            for accent in AppAccentChoice.allCases {
                let palette = AppThemePalette.make(theme: theme, accent: accent, dark: theme == .oled)
                AppThemeUIKit.update(tabs, palette: palette)
                XCTAssertTrue(tabs.selectedViewController === navigation)
                XCTAssertTrue(navigation.topViewController === screen)
                XCTAssertTrue(screen.view === originalView)
                XCTAssertTrue(collection.superview === originalView)
                XCTAssertEqual(collection.backgroundColor, .magenta)
                XCTAssertEqual(navigation.navigationBar.standardAppearance.backgroundColor, palette.background.uiColor)
            }
        }
    }

    @MainActor
    func testThemeAndFontAppearanceCopiesPreserveEachOthersAttributes() throws {
        let source = UINavigationBarAppearance()
        let font = UIFont.italicSystemFont(ofSize: 19)
        source.titleTextAttributes = [.font: font, .kern: 1.5]
        let palette = AppThemePalette.make(theme: .oled, accent: .carmine, dark: true)
        let themed = AppThemeUIKit.navigation(source, palette: palette)
        XCTAssertEqual(themed.titleTextAttributes[.font] as? UIFont, font)
        XCTAssertEqual(themed.titleTextAttributes[.kern] as? Double, 1.5)
        let withSystemFont = AppFont.navigationAppearance(from: themed, typeface: .sfPro)
        XCTAssertEqual(withSystemFont.backgroundColor, palette.background.uiColor)
        XCTAssertEqual(withSystemFont.titleTextAttributes[.foregroundColor] as? UIColor, palette.text.uiColor)
        let withThemeAfterFont = AppThemeUIKit.navigation(withSystemFont, palette: palette)
        XCTAssertEqual(withThemeAfterFont.titleTextAttributes[.font] as? UIFont, withSystemFont.titleTextAttributes[.font] as? UIFont)
        let tab = UITabBarAppearance()
        tab.stackedLayoutAppearance.normal.titleTextAttributes[.font] = font
        let themedTab = AppThemeUIKit.tabs(tab, palette: palette)
        XCTAssertEqual(themedTab.stackedLayoutAppearance.normal.titleTextAttributes[.font] as? UIFont, font)
    }

    func testSmallPositiveDonutCountsRemainVisibleAndZerosDoNotGetAnArc() {
        let values = [55, 4, 755, 4, 2]
        let spans = ProfileDonutLayout.spans(values: values)
        XCTAssertEqual(spans.count, values.count)
        XCTAssertTrue(spans.allSatisfy { $0.length > 0 })
        let withZeros = ProfileDonutLayout.spans(values: [55, 0, 755, 0, 2])
        XCTAssertEqual(withZeros[1].length, 0)
        XCTAssertEqual(withZeros[3].length, 0)
        XCTAssertGreaterThan(withZeros[4].length, 0)
    }

    func testDonutHandlesHugeCountsWithoutIntOverflowOrInvisibleNonzeroValues() {
        let spans = ProfileDonutLayout.spans(values: [Int.max, 1, 1, 0, 0])
        XCTAssertTrue(spans.allSatisfy { $0.start.isFinite && $0.end.isFinite && $0.end >= $0.start })
        XCTAssertGreaterThan(spans[1].length, 0)
        XCTAssertGreaterThan(spans[2].length, 0)
        XCTAssertTrue(ProfileDonutLayout.spans(values: []).isEmpty)
        XCTAssertTrue(ProfileDonutLayout.spans(values: [0, -1, 0]).isEmpty)
        XCTAssertEqual(ProfileDonutLayout.spans(values: [5])[0].length, 1)
    }

    func testForeignReputationCopyNeverClaimsItBelongsToTheViewer() {
        let text = ProfileReputationCopy.foreign(login: "Другой пользователь", score: 5)
        XCTAssertTrue(text.contains("Другой пользователь"))
        XCTAssertTrue(text.contains("5"))
        XCTAssertFalse(text.lowercased().contains("ваш"))
        XCTAssertFalse(text.lowercased().contains("твой"))
        XCTAssertTrue(text.contains("владельца этого профиля"))
    }

    func testUpgradePromptDoesNotBlockAnExistingBlogAfterReputationFalls() throws {
        let profile = try profileTestDecode(Profile.self, #"{"id":42,"rating_score":1}"#)
        let channel = try profileTestDecode(Channel.self, #"{"id":71,"is_blog":true,"blog_profile_id":42}"#)
        XCTAssertTrue(ProfileBlogEntryPolicy.requiresUpgrade(profile: profile, channel: nil, minimum: 3))
        XCTAssertFalse(ProfileBlogEntryPolicy.requiresUpgrade(profile: profile, channel: channel, minimum: 3))
        XCTAssertEqual(ProfileBlogEntryPolicy.progress(score: 1, minimum: 3), 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(ProfileBlogEntryPolicy.progress(score: -1, minimum: 3), 0)
        XCTAssertEqual(ProfileBlogEntryPolicy.progress(score: 10, minimum: 3), 1)
    }

    @MainActor
    func testOriginalMascotIsBundledAndUsesOriginalRendering() throws {
        XCTAssertNotNil(Bundle.main.url(forResource: "anixa_wow", withExtension: "webp"))
        let image = try XCTUnwrap(ProfileMascotArtwork.image)
        XCTAssertEqual(image.renderingMode, .alwaysOriginal)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    @MainActor
    private func enqueueProfile(_ rig: ProfileTestRig, blog: String) {
        rig.api.enqueue("/profile/42", json: #"{"code":0,"profile":{"id":42,"rating_score":1,"is_social_hidden":true}}"#)
        rig.api.enqueue("/profile/42/badge/list", json: #"{"code":0,"sections":[],"showcased":[]}"#)
        rig.api.enqueue("/channel/blog/42", json: blog)
    }

    @MainActor
    func testSignedInUncreatedBlogIsNormalAbsenceNotLoadingError() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = ProfileViewModel()
        enqueueProfile(rig, blog: #"{"code":2}"#)
        await model.load(profileID: 42, session: rig.session)
        XCTAssertNil(model.blog)
        XCTAssertNil(model.blogErrorMessage)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.profile?.id, 42)
    }

    @MainActor
    func testExplicitMissingBlogClearsAnOldCoverButMalformedReadDoesNotHideItsFailure() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = ProfileViewModel()
        enqueueProfile(rig, blog: #"{"code":0,"channel":{"id":71,"blog_profile_id":42,"cover":"https://example.invalid/cover.jpg"}}"#)
        await model.load(profileID: 42, session: rig.session)
        XCTAssertNotNil(model.coverURL)
        enqueueProfile(rig, blog: #"{"code":2}"#)
        await model.load(profileID: 42, session: rig.session)
        XCTAssertNil(model.coverURL)
        XCTAssertNil(model.blogErrorMessage)
        enqueueProfile(rig, blog: "{}")
        await model.load(profileID: 42, session: rig.session)
        XCTAssertNotNil(model.blogErrorMessage)
    }
}
