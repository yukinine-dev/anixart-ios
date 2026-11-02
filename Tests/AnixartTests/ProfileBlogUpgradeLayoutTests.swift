import SwiftUI
import UIKit
import XCTest
@testable import Anixart

final class ProfileBlogUpgradeLayoutTests: XCTestCase {
    func testExplanationUsesTheAvailableSafeHeightRatherThanTheOld78PercentCap() {
        let available = CGSize(width: 393, height: 759)
        let layout = ProfileBlogUpgradeLayout(available: available)
        XCTAssertEqual(layout.size, CGSize(width: 369, height: 735))
        XCTAssertGreaterThan(layout.size.height, available.height * 0.78)
        XCTAssertLessThan(layout.artworkHeight, 180)
    }

    func testZeroSmallLandscapeAndTabletProposalsStayBounded() {
        for available in [CGSize.zero, CGSize(width: 12, height: 20), CGSize(width: 320, height: 480),
                          CGSize(width: 740, height: 320), CGSize(width: 1_024, height: 1_300)] {
            let layout = ProfileBlogUpgradeLayout(available: available)
            XCTAssertGreaterThanOrEqual(layout.size.width, 0)
            XCTAssertGreaterThanOrEqual(layout.size.height, 0)
            XCTAssertLessThanOrEqual(layout.size.width, min(420, available.width))
            XCTAssertLessThanOrEqual(layout.size.height, min(840, available.height))
            XCTAssertLessThanOrEqual(layout.artworkHeight, min(180, layout.size.height))
        }
        let invalid = ProfileBlogUpgradeLayout(available: CGSize(width: CGFloat.nan, height: CGFloat.infinity))
        XCTAssertEqual(invalid.size, .zero)
        XCTAssertEqual(invalid.artworkHeight, 0)
    }

    func testShortWindowsReduceDecorationInsteadOfRemovingCoverInformation() {
        let portrait = ProfileBlogUpgradeLayout(available: CGSize(width: 393, height: 759))
        let landscape = ProfileBlogUpgradeLayout(available: CGSize(width: 759, height: 300))
        XCTAssertLessThan(landscape.artworkHeight, portrait.artworkHeight)
        XCTAssertEqual(ProfileBlogUpgradeFeature.allCases, [.posts, .channels, .cover])
        XCTAssertEqual(ProfileBlogUpgradeFeature.cover.title, "Установка обложки профиля")
        XCTAssertFalse(ProfileBlogUpgradeFeature.cover.detail.isEmpty)
    }

    @MainActor
    func testPortraitContentIncludingCoverFitsAboveTheAlwaysVisibleCloseControl() throws {
        XCTAssertNotNil(ProfileMascotArtwork.image)
        for available in [CGSize(width: 393, height: 759), CGSize(width: 430, height: 839)] {
            for theme in [ColorScheme.light, .dark] {
                let layout = ProfileBlogUpgradeLayout(available: available)
                let content = measure(ProfileBlogUpgradeContent(score: 1, minimum: 3, artworkHeight: layout.artworkHeight) {},
                                      width: layout.size.width, textSize: .large, theme: theme)
                let close = measure(ProfileBlogUpgradeCloseButton {}, width: layout.size.width, textSize: .large, theme: theme)
                XCTAssertLessThanOrEqual(content.height + close.height, layout.size.height + 0.5)
                XCTAssertGreaterThanOrEqual(close.height, 44)
            }
        }
    }

    @MainActor
    func testLargeTextRemainsFullHeightScrollableContentRatherThanTruncatedRows() {
        let layout = ProfileBlogUpgradeLayout(available: CGSize(width: 393, height: 759))
        let normal = measure(ProfileBlogUpgradeContent(score: 1, minimum: 3, artworkHeight: layout.artworkHeight) {},
                             width: layout.size.width, textSize: .large)
        let enlarged = measure(ProfileBlogUpgradeContent(score: 1, minimum: 3, artworkHeight: layout.artworkHeight) {},
                               width: layout.size.width, textSize: .accessibility3)
        XCTAssertGreaterThan(enlarged.height, normal.height)
        XCTAssertGreaterThan(enlarged.height, layout.size.height)
        XCTAssertTrue(ProfileBlogUpgradeContent.publishingLimitation.contains("В iOS"))
        XCTAssertTrue(ProfileBlogUpgradeContent.publishingLimitation.contains("пока не поддерживается"))
    }

    @MainActor
    func testMeasuringReadOnlyExplanationDoesNotActivateHelpOrClose() {
        var actions = 0
        let layout = ProfileBlogUpgradeLayout(available: CGSize(width: 393, height: 759))
        _ = measure(ProfileBlogUpgradeContent(score: 1, minimum: 3, artworkHeight: layout.artworkHeight) { actions += 1 },
                    width: layout.size.width, textSize: .large)
        _ = measure(ProfileBlogUpgradeCloseButton { actions += 1 }, width: layout.size.width, textSize: .large)
        XCTAssertEqual(actions, 0)
    }

    @MainActor
    private func measure<Content: View>(_ content: Content, width: CGFloat, textSize: DynamicTypeSize,
                                       theme: ColorScheme = .light) -> CGSize {
        let host = UIHostingController(rootView: content
            .dynamicTypeSize(textSize)
            .environment(\.colorScheme, theme)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true))
        return host.sizeThatFits(in: CGSize(width: width, height: 10_000))
    }
}
