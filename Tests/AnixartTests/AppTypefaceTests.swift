import Foundation
import Observation
import SwiftUI
import UIKit
import XCTest
@testable import Anixart

final class AppTypefaceTests: XCTestCase {
    private let styles: [(Font.TextStyle, CGFloat)] = [
        (.largeTitle, 34), (.title, 28), (.title2, 22), (.title3, 20),
        (.headline, 17), (.body, 17), (.callout, 16), (.subheadline, 15),
        (.footnote, 13), (.caption, 12), (.caption2, 11)
    ]

    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "AppTypefaceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testMissingPreferenceDefaultsToRobotoWithoutWriting() throws {
        let defaults = try isolatedDefaults()
        let preferences = AppTypefacePreferences(defaults: defaults)
        XCTAssertEqual(preferences.typeface, .roboto)
        XCTAssertNil(defaults.object(forKey: AppFont.preferenceStorageKey))
        XCTAssertEqual(AppTypeface(storedValue: nil), .roboto)
    }

    func testInvalidPersistedPreferenceUsesRoboto() throws {
        let defaults = try isolatedDefaults()
        let invalidValues: [Any] = ["", "system", "SF Pro", "Roboto", 42, true, ["sfPro"], ["font": "sfPro"]]
        for value in invalidValues {
            defaults.set(value, forKey: AppFont.preferenceStorageKey)
            XCTAssertEqual(AppTypefacePreferences(defaults: defaults).typeface, .roboto, "\(value)")
        }
    }

    func testPickerChoicesHaveStableStorageValuesAndTitles() {
        XCTAssertEqual(AppFont.preferenceStorageKey, "appearance.typeface")
        XCTAssertEqual(AppTypeface.allCases, [.roboto, .sfPro])
        XCTAssertEqual(AppTypeface.allCases.map(\.rawValue), ["roboto", "sfPro"])
        XCTAssertEqual(AppTypeface.allCases.map(\.id), ["roboto", "sfPro"])
        XCTAssertEqual(AppTypeface.roboto.title, "Roboto")
        XCTAssertTrue(AppTypeface.sfPro.title.contains("SF Pro"))
        for choice in AppTypeface.allCases {
            XCTAssertEqual(AppTypeface(storedValue: choice.rawValue), choice)
        }
    }

    @MainActor
    func testSelectedTypefacePersistsAcrossInstances() throws {
        let defaults = try isolatedDefaults()
        let preferences = AppTypefacePreferences(defaults: defaults)
        preferences.setTypeface(.sfPro)
        XCTAssertEqual(preferences.typeface, .sfPro)
        XCTAssertEqual(defaults.string(forKey: AppFont.preferenceStorageKey), "sfPro")
        let restored = AppTypefacePreferences(defaults: defaults)
        XCTAssertEqual(restored.typeface, .sfPro)
        restored.setTypeface(.roboto)
        XCTAssertEqual(defaults.string(forKey: AppFont.preferenceStorageKey), "roboto")
        XCTAssertEqual(AppTypefacePreferences(defaults: defaults).typeface, .roboto)
    }

    @MainActor
    func testReloadHandlesExternalChangesRemovalAndInvalidValues() throws {
        let defaults = try isolatedDefaults()
        let preferences = AppTypefacePreferences(defaults: defaults)
        defaults.set("sfPro", forKey: AppFont.preferenceStorageKey)
        preferences.reload()
        XCTAssertEqual(preferences.typeface, .sfPro)
        defaults.set("unknown", forKey: AppFont.preferenceStorageKey)
        preferences.reload()
        XCTAssertEqual(preferences.typeface, .roboto)
        // A reload resolves invalid data but does not silently rewrite it.
        XCTAssertEqual(defaults.string(forKey: AppFont.preferenceStorageKey), "unknown")
        preferences.setTypeface(.sfPro)
        defaults.removeObject(forKey: AppFont.preferenceStorageKey)
        preferences.reload()
        XCTAssertEqual(preferences.typeface, .roboto)
        XCTAssertNil(defaults.object(forKey: AppFont.preferenceStorageKey))
    }

    @MainActor
    func testFontChoiceParticipatesInObservationWithoutReplacingStore() async throws {
        let preferences = AppTypefacePreferences(defaults: try isolatedDefaults())
        let identity = ObjectIdentifier(preferences)
        let initial = Font.ax(.body, preferences: preferences)
        let initialFixed = Font.ax(fixed: 13, preferences: preferences)
        let changed = expectation(description: "The text-style font helper's preference read is observed")
        let fixedChanged = expectation(description: "The fixed-size font helper's preference read is observed")
        withObservationTracking {
            _ = Font.ax(.body, preferences: preferences)
        } onChange: {
            changed.fulfill()
        }
        withObservationTracking {
            _ = Font.ax(fixed: 13, preferences: preferences)
        } onChange: {
            fixedChanged.fulfill()
        }
        preferences.setTypeface(.sfPro)
        await fulfillment(of: [changed, fixedChanged], timeout: 1)
        XCTAssertEqual(ObjectIdentifier(preferences), identity)
        XCTAssertNotEqual(Font.ax(.body, preferences: preferences), initial)
        XCTAssertNotEqual(Font.ax(fixed: 13, preferences: preferences), initialFixed)
    }

    func testLegacyRobotoWeightNamesAndStyleSizesRemainUnchanged() {
        XCTAssertEqual(AppFont.family, "Roboto")
        for weight in [Font.Weight.ultraLight, .thin, .light, .regular] {
            XCTAssertEqual(AppFont.name(for: weight), "Roboto-Regular")
        }
        for weight in [Font.Weight.medium, .semibold] {
            XCTAssertEqual(AppFont.name(for: weight), "Roboto-Medium")
        }
        for weight in [Font.Weight.bold, .heavy, .black] {
            XCTAssertEqual(AppFont.name(for: weight), "Roboto-Bold")
        }
        for (style, size) in styles {
            XCTAssertEqual(AppFont.size(of: style), size)
        }
    }

    func testSwiftUIFontConstructorsPreserveDynamicTypeAndFixedSizeSemantics() {
        for (style, size) in styles {
            let weight: Font.Weight = style == .headline ? .medium : .regular
            XCTAssertEqual(Font.ax(style, typeface: .roboto),
                           .custom(AppFont.name(for: weight), size: size, relativeTo: style))
            XCTAssertEqual(Font.ax(style, typeface: .sfPro), .system(style, design: .default).weight(weight))
        }
        XCTAssertEqual(Font.ax(.title3, .bold, typeface: .sfPro), .system(.title3, design: .default).weight(.bold))
        XCTAssertEqual(Font.ax(.headline, .regular, typeface: .roboto),
                       .custom("Roboto-Regular", size: 17, relativeTo: .headline))
        XCTAssertEqual(Font.ax(fixed: 13, .semibold, typeface: .roboto), .custom("Roboto-Medium", fixedSize: 13))
        XCTAssertEqual(Font.ax(fixed: 13, .semibold, typeface: .sfPro), .system(size: 13, weight: .semibold, design: .default))
    }

    @MainActor
    func testUIFontChoosesBundledRobotoAndNativeSystemForAllWeights() throws {
        let weights: [(Font.Weight, UIFont.Weight)] = [
            (.ultraLight, .ultraLight), (.thin, .thin), (.light, .light), (.regular, .regular),
            (.medium, .medium), (.semibold, .semibold), (.bold, .bold), (.heavy, .heavy), (.black, .black)
        ]
        for (weight, uiWeight) in weights {
            let bundled = try XCTUnwrap(UIFont(name: AppFont.name(for: weight), size: 19))
            let roboto = AppFont.uiFont(fixed: 19, weight, typeface: .roboto)
            XCTAssertEqual(roboto.fontName, bundled.fontName)
            XCTAssertEqual(roboto.pointSize, 19)
            let native = UIFont.systemFont(ofSize: 19, weight: uiWeight)
            let system = AppFont.uiFont(fixed: 19, weight, typeface: .sfPro)
            XCTAssertEqual(system.fontName, native.fontName)
            XCTAssertEqual(system.familyName, native.familyName)
            XCTAssertEqual(system.fontDescriptor.symbolicTraits, native.fontDescriptor.symbolicTraits)
            XCTAssertEqual(system.pointSize, 19)
        }
    }

    @MainActor
    func testUIKitDynamicTypeScalesBothChoicesForEveryTextStyle() {
        let standard = UITraitCollection(preferredContentSizeCategory: .large)
        let accessible = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        for typeface in AppTypeface.allCases {
            for (style, size) in styles {
                let baseline = AppFont.uiFont(style, typeface: typeface, compatibleWith: standard)
                let scaled = AppFont.uiFont(style, typeface: typeface, compatibleWith: accessible)
                XCTAssertEqual(baseline.pointSize, size, accuracy: 0.01)
                XCTAssertGreaterThan(scaled.pointSize, baseline.pointSize, "\(typeface), \(style)")
            }
        }
    }

    @MainActor
    func testBarFontsHonorCompatibleDynamicTypeTraits() throws {
        let standard = UITraitCollection(preferredContentSizeCategory: .large)
        let accessible = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        let navigation = UINavigationBar()
        let tab = UITabBar()
        for typeface in AppTypeface.allCases {
            AppFont.apply(typeface, to: navigation, compatibleWith: standard)
            AppFont.apply(typeface, to: tab, compatibleWith: standard)
            let titleSize = try XCTUnwrap(navigation.standardAppearance.titleTextAttributes[.font] as? UIFont).pointSize
            let largeTitleSize = try XCTUnwrap(navigation.standardAppearance.largeTitleTextAttributes[.font] as? UIFont).pointSize
            let tabSize = try XCTUnwrap(tab.standardAppearance.stackedLayoutAppearance.normal.titleTextAttributes[.font] as? UIFont).pointSize
            AppFont.apply(typeface, to: navigation, compatibleWith: accessible)
            AppFont.apply(typeface, to: tab, compatibleWith: accessible)
            XCTAssertGreaterThan(try XCTUnwrap(navigation.standardAppearance.titleTextAttributes[.font] as? UIFont).pointSize, titleSize)
            XCTAssertGreaterThan(try XCTUnwrap(navigation.standardAppearance.largeTitleTextAttributes[.font] as? UIFont).pointSize, largeTitleSize)
            XCTAssertGreaterThan(try XCTUnwrap(tab.standardAppearance.stackedLayoutAppearance.normal.titleTextAttributes[.font] as? UIFont).pointSize, tabSize)
        }
    }

    @MainActor
    func testNavigationFontUpdatePreservesAllAppearanceVariantsAndThemeAttributes() throws {
        let bar = UINavigationBar()
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        let original = UINavigationBarAppearance()
        original.configureWithOpaqueBackground()
        original.backgroundColor = .orange
        original.shadowColor = .purple
        original.titleTextAttributes = [.font: UIFont.italicSystemFont(ofSize: 14), .foregroundColor: UIColor.red, .kern: 1.5]
        original.largeTitleTextAttributes = [.font: UIFont.italicSystemFont(ofSize: 28), .foregroundColor: UIColor.green]
        original.buttonAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.brown]
        bar.standardAppearance = original
        let edge = original.copy() as! UINavigationBarAppearance
        edge.backgroundColor = .blue
        bar.scrollEdgeAppearance = edge
        let compact = original.copy() as! UINavigationBarAppearance
        compact.backgroundColor = .yellow
        bar.compactAppearance = compact
        let compactEdge = original.copy() as! UINavigationBarAppearance
        compactEdge.backgroundColor = .cyan
        bar.compactScrollEdgeAppearance = compactEdge
        let source = bar.standardAppearance

        AppFont.apply(.sfPro, to: bar, compatibleWith: traits)

        XCTAssertFalse(bar.standardAppearance === source)
        XCTAssertEqual((source.titleTextAttributes[.font] as? UIFont)?.pointSize, 14)
        let variants: [(UINavigationBarAppearance?, UIColor)] = [
            (bar.standardAppearance, .orange), (bar.scrollEdgeAppearance, .blue),
            (bar.compactAppearance, .yellow), (bar.compactScrollEdgeAppearance, .cyan)
        ]
        for (variant, background) in variants {
            let appearance = try XCTUnwrap(variant)
            XCTAssertEqual(appearance.backgroundColor, background)
            XCTAssertEqual(appearance.shadowColor, .purple)
            XCTAssertEqual(appearance.titleTextAttributes[.foregroundColor] as? UIColor, .red)
            XCTAssertEqual(appearance.titleTextAttributes[.kern] as? Double, 1.5)
            XCTAssertEqual(appearance.largeTitleTextAttributes[.foregroundColor] as? UIColor, .green)
            XCTAssertEqual(appearance.buttonAppearance.normal.titleTextAttributes[.foregroundColor] as? UIColor, .brown)
            let title = try XCTUnwrap(appearance.titleTextAttributes[.font] as? UIFont)
            let largeTitle = try XCTUnwrap(appearance.largeTitleTextAttributes[.font] as? UIFont)
            XCTAssertEqual(title.pointSize, 17, accuracy: 0.01)
            XCTAssertEqual(largeTitle.pointSize, 34, accuracy: 0.01)
            XCTAssertEqual(title.familyName, UIFont.systemFont(ofSize: 17, weight: .medium).familyName)
            XCTAssertEqual(largeTitle.familyName, UIFont.systemFont(ofSize: 34, weight: .bold).familyName)
        }
    }

    @MainActor
    func testTabFontUpdatePreservesLayoutStatesAndThemeAttributes() throws {
        let bar = UITabBar()
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        let original = UITabBarAppearance()
        original.configureWithOpaqueBackground()
        original.backgroundColor = .orange
        original.shadowColor = .purple
        for item in [original.stackedLayoutAppearance, original.inlineLayoutAppearance, original.compactInlineLayoutAppearance] {
            item.normal.iconColor = .brown
            item.selected.iconColor = .yellow
            item.normal.badgeBackgroundColor = .red
            item.selected.titlePositionAdjustment = UIOffset(horizontal: 2, vertical: 3)
            for state in [item.normal, item.selected, item.disabled, item.focused] {
                state.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 5), .foregroundColor: UIColor.cyan, .kern: 0.5]
            }
        }
        bar.standardAppearance = original
        let edge = original.copy() as! UITabBarAppearance
        edge.backgroundColor = .blue
        bar.scrollEdgeAppearance = edge
        let source = bar.standardAppearance
        let tabItem = UITabBarItem(title: "Профиль", image: nil, tag: 0)
        tabItem.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 6), .foregroundColor: UIColor.green], for: .normal)
        tabItem.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 7), .foregroundColor: UIColor.red], for: .selected)
        bar.items = [tabItem]

        AppFont.apply(.sfPro, to: bar, compatibleWith: traits)

        XCTAssertFalse(bar.standardAppearance === source)
        XCTAssertEqual((source.stackedLayoutAppearance.normal.titleTextAttributes[.font] as? UIFont)?.pointSize, 5)
        XCTAssertEqual(tabItem.titleTextAttributes(for: .normal)?[.foregroundColor] as? UIColor, .green)
        XCTAssertEqual(tabItem.titleTextAttributes(for: .selected)?[.foregroundColor] as? UIColor, .red)
        for state in [UIControl.State.normal, .selected, .disabled, .focused] {
            let font = try XCTUnwrap(tabItem.titleTextAttributes(for: state)?[.font] as? UIFont)
            XCTAssertEqual(font.pointSize, 10, accuracy: 0.01)
            XCTAssertEqual(font.familyName, UIFont.systemFont(ofSize: 10, weight: .medium).familyName)
        }
        let variants: [(UITabBarAppearance, UIColor)] = [
            (bar.standardAppearance, .orange), (try XCTUnwrap(bar.scrollEdgeAppearance), .blue)
        ]
        for (variant, background) in variants {
            XCTAssertEqual(variant.backgroundColor, background)
            XCTAssertEqual(variant.shadowColor, .purple)
            for item in [variant.stackedLayoutAppearance, variant.inlineLayoutAppearance, variant.compactInlineLayoutAppearance] {
                XCTAssertEqual(item.normal.iconColor, .brown)
                XCTAssertEqual(item.selected.iconColor, .yellow)
                XCTAssertEqual(item.normal.badgeBackgroundColor, .red)
                XCTAssertEqual(item.selected.titlePositionAdjustment.horizontal, 2)
                XCTAssertEqual(item.selected.titlePositionAdjustment.vertical, 3)
                for state in [item.normal, item.selected, item.disabled, item.focused] {
                    XCTAssertEqual(state.titleTextAttributes[.foregroundColor] as? UIColor, .cyan)
                    XCTAssertEqual(state.titleTextAttributes[.kern] as? Double, 0.5)
                    let font = try XCTUnwrap(state.titleTextAttributes[.font] as? UIFont)
                    XCTAssertEqual(font.pointSize, 10, accuracy: 0.01)
                    XCTAssertEqual(font.familyName, UIFont.systemFont(ofSize: 10, weight: .medium).familyName)
                }
            }
        }
    }

    @MainActor
    func testThemeAppearanceTemplatesReceiveFontsWithoutLosingColors() {
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        let navigation = UINavigationBarAppearance()
        navigation.backgroundColor = .orange
        navigation.titleTextAttributes = [.foregroundColor: UIColor.green]
        let tab = UITabBarAppearance()
        tab.backgroundColor = .purple
        tab.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.red]
        // UIKit can supply default fonts even when only a colour was assigned.
        // Verify that font-only copies leave the actual original attributes intact.
        let originalNavigationAttributes = navigation.titleTextAttributes as NSDictionary
        let originalTabAttributes = tab.stackedLayoutAppearance.selected.titleTextAttributes as NSDictionary
        let updatedNavigation = AppFont.navigationAppearance(from: navigation, typeface: .sfPro, compatibleWith: traits)
        let updatedTab = AppFont.tabAppearance(from: tab, typeface: .sfPro, compatibleWith: traits)
        XCTAssertEqual(updatedNavigation.backgroundColor, .orange)
        XCTAssertEqual(updatedNavigation.titleTextAttributes[.foregroundColor] as? UIColor, .green)
        XCTAssertEqual(updatedTab.backgroundColor, .purple)
        XCTAssertEqual(updatedTab.stackedLayoutAppearance.selected.titleTextAttributes[.foregroundColor] as? UIColor, .red)
        XCTAssertNotNil(updatedNavigation.titleTextAttributes[.font] as? UIFont)
        XCTAssertNotNil(updatedTab.stackedLayoutAppearance.selected.titleTextAttributes[.font] as? UIFont)
        XCTAssertEqual(navigation.titleTextAttributes as NSDictionary, originalNavigationAttributes)
        XCTAssertEqual(tab.stackedLayoutAppearance.selected.titleTextAttributes as NSDictionary, originalTabAttributes)
        XCTAssertEqual(navigation.backgroundColor, .orange)
        XCTAssertEqual(tab.backgroundColor, .purple)
    }

    @MainActor
    func testNilBarAppearanceFallbacksRemainNil() {
        let navigation = UINavigationBar()
        navigation.scrollEdgeAppearance = nil
        navigation.compactAppearance = nil
        navigation.compactScrollEdgeAppearance = nil
        AppFont.apply(.sfPro, to: navigation)
        XCTAssertNil(navigation.scrollEdgeAppearance)
        XCTAssertNil(navigation.compactAppearance)
        XCTAssertNil(navigation.compactScrollEdgeAppearance)
        let tab = UITabBar()
        tab.scrollEdgeAppearance = nil
        AppFont.apply(.sfPro, to: tab)
        XCTAssertNil(tab.scrollEdgeAppearance)
    }

    @MainActor
    func testLoadedHierarchyFontUpdatesKeepNavigationAndTabState() throws {
        let first = UINavigationController(rootViewController: UIViewController())
        let secondRoot = UIViewController()
        let detail = UIViewController()
        let second = UINavigationController(rootViewController: secondRoot)
        second.pushViewController(detail, animated: false)
        let tabs = UITabBarController()
        tabs.setViewControllers([first, second], animated: false)
        tabs.selectedIndex = 1
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        tabs.loadViewIfNeeded()
        tabs.view.frame = container.bounds
        container.addSubview(tabs.view)
        second.loadViewIfNeeded()
        tabs.view.layoutIfNeeded()

        for typeface in AppTypeface.allCases {
            AppFont.applyToUIKitBars(in: container, typeface: typeface)
            XCTAssertEqual(tabs.selectedIndex, 1)
            XCTAssertTrue(tabs.selectedViewController === second)
            XCTAssertEqual(second.viewControllers.count, 2)
            XCTAssertTrue(second.viewControllers.first === secondRoot)
            XCTAssertTrue(second.topViewController === detail)
            let title = try XCTUnwrap(second.navigationBar.standardAppearance.titleTextAttributes[.font] as? UIFont)
            let caption = try XCTUnwrap(tabs.tabBar.standardAppearance.stackedLayoutAppearance.normal.titleTextAttributes[.font] as? UIFont)
            let expectedTitle = AppFont.uiFont(.headline, .medium, typeface: typeface,
                                              compatibleWith: second.navigationBar.traitCollection)
            let expectedCaption = UIFontMetrics(forTextStyle: .caption2).scaledFont(
                for: AppFont.uiFont(fixed: 10, .medium, typeface: typeface), compatibleWith: tabs.tabBar.traitCollection)
            XCTAssertEqual(title.fontName, expectedTitle.fontName)
            XCTAssertEqual(title.pointSize, expectedTitle.pointSize, accuracy: 0.01)
            XCTAssertEqual(caption.fontName, expectedCaption.fontName)
            XCTAssertEqual(caption.pointSize, expectedCaption.pointSize, accuracy: 0.01)
        }
    }
}
