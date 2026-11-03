import SwiftUI
import UIKit
import XCTest
import AnixartKit
@testable import Anixart

final class ReleaseDetailHeaderTests: XCTestCase {
    @MainActor
    func testDetailRestoresTheLargePosterNotAListThumbnail() {
        XCTAssertEqual(ReleaseDetailHeader.posterHeight, 340)
        XCTAssertGreaterThan(ReleaseDetailHeader.backdropHeight, ReleaseDetailHeader.posterHeight)
    }

    func testMoreButtonRequiresActuallyHiddenLinesNotJustANonemptyDescription() {
        XCTAssertFalse(ReleaseTextTruncation.needsExpansion(fullHeight: 0, visibleHeight: 0))
        XCTAssertFalse(ReleaseTextTruncation.needsExpansion(fullHeight: 48, visibleHeight: 48))
        XCTAssertFalse(ReleaseTextTruncation.needsExpansion(fullHeight: 48.5, visibleHeight: 48))
        XCTAssertTrue(ReleaseTextTruncation.needsExpansion(fullHeight: 96, visibleHeight: 48))
    }

    @MainActor
    func testHeaderStaysWithinPhoneWidthsAndMeasurementDoesNotInvokeActions() throws {
        let release = try profileTestDecode(Release.self, #"{"id":71,"title_ru":"Длинное название релиза для проверки переноса","title_original":"Original title","age_rating":5,"description":"Описание должно быть ниже характеристик, не в шапке."}"#)
        XCTAssertEqual(release.ageRatingText, "18+")
        var actions = 0
        for width in [CGFloat(320), 375, 768] {
            for size in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
                let header = ReleaseDetailHeader(release: release, onTitles: { actions += 1 })
                let host = UIHostingController(rootView: header.dynamicTypeSize(size).frame(width: width)
                    .fixedSize(horizontal: false, vertical: true))
                let measured = host.sizeThatFits(in: CGSize(width: width, height: 10_000))
                XCTAssertLessThanOrEqual(measured.width, width + 0.5)
                XCTAssertGreaterThan(measured.height, ReleaseDetailHeader.backdropHeight)
                XCTAssertTrue(measured.height.isFinite)
            }
        }
        XCTAssertEqual(actions, 0)
    }

    func testCreditsShareOneFactAndKeepThreeIndependentUnderlinedSearchLinks() throws {
        let release = try profileTestDecode(Release.self, #"{"id":71,"studio":" Studio ","author":"Author","director":"Director"}"#)
        let entries = ReleaseCredit.entries(for: release)
        XCTAssertEqual(entries.map(\.scope), [.studio, .author, .director])
        let text = ReleaseCredit.text(for: entries)
        XCTAssertEqual(String(text.characters), "Студия Studio, автор Author, режиссёр Director")
        let links = text.runs.compactMap { $0.link }
        XCTAssertEqual(links, entries.map(\.url))
        XCTAssertEqual(text.runs.filter { $0.underlineStyle == .single }.count, 3)
        let empty = try profileTestDecode(Release.self, #"{"id":72,"studio":"  ","author":"\n"}"#)
        XCTAssertTrue(ReleaseCredit.entries(for: empty).isEmpty)
    }
}
