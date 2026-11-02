import SwiftUI
import UIKit
import XCTest
import AnixartKit
@testable import Anixart

final class ReleaseDetailHeaderTests: XCTestCase {
    func testColumnsFitRegularPhonesAndStackForNarrowOrLargeText() {
        XCTAssertTrue(ReleaseHeaderLayout.usesColumns(availableWidth: 343, largeText: false))
        XCTAssertTrue(ReleaseHeaderLayout.usesColumns(availableWidth: 800, largeText: false))
        XCTAssertTrue(ReleaseHeaderLayout.usesColumns(availableWidth: 324, largeText: false))
        XCTAssertFalse(ReleaseHeaderLayout.usesColumns(availableWidth: 323, largeText: false))
        XCTAssertFalse(ReleaseHeaderLayout.usesColumns(availableWidth: 288, largeText: false))
        XCTAssertFalse(ReleaseHeaderLayout.usesColumns(availableWidth: 800, largeText: true))
    }

    func testMoreButtonRequiresActuallyHiddenLinesNotJustANonemptyDescription() {
        XCTAssertFalse(ReleaseTextTruncation.needsExpansion(fullHeight: 0, visibleHeight: 0))
        XCTAssertFalse(ReleaseTextTruncation.needsExpansion(fullHeight: 48, visibleHeight: 48))
        XCTAssertFalse(ReleaseTextTruncation.needsExpansion(fullHeight: 48.5, visibleHeight: 48))
        XCTAssertTrue(ReleaseTextTruncation.needsExpansion(fullHeight: 96, visibleHeight: 48))
    }

    @MainActor
    func testHeaderStaysWithinPhoneWidthsAndMeasurementDoesNotInvokeActions() throws {
        let release = try profileTestDecode(Release.self, #"{"id":71,"title_ru":"Длинное название релиза для проверки переноса","episodes_released":5,"episodes_total":12,"grade":4.2,"status_id":2,"description":"Начало описания рядом с постером. Остальной текст должен переноситься и оставаться доступным при увеличенном размере шрифта."}"#)
        var actions = 0
        for width in [CGFloat(320), 375, 768] {
            for size in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
                let header = ReleaseDetailHeader(release: release, isDescriptionExpanded: .constant(false),
                                                 onTitles: { actions += 1 }, onExpand: { _ in actions += 1 })
                let host = UIHostingController(rootView: header.dynamicTypeSize(size).frame(width: width)
                    .fixedSize(horizontal: false, vertical: true))
                let measured = host.sizeThatFits(in: CGSize(width: width, height: 10_000))
                XCTAssertLessThanOrEqual(measured.width, width + 0.5)
                XCTAssertGreaterThan(measured.height, 0)
                XCTAssertTrue(measured.height.isFinite)
            }
        }
        XCTAssertEqual(actions, 0)
    }
}
