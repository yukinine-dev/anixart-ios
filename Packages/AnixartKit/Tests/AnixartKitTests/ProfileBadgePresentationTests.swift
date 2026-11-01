import Foundation
import XCTest
@testable import AnixartKit

/// Synthetic, offline fixtures. They are not observations of a public profile.
final class ProfileBadgePresentationTests: XCTestCase {
    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func badges(_ count: Int, lastPinned: Bool = false) throws -> [Badge] {
        try (0..<count).map { index in
            try decode(Badge.self, "{\"id\":\(index + 1),\"is_showcased\":\(lastPinned && index == count - 1)}")
        }
    }

    func testOrdinaryFullRowReservesItsLastSlotForOverflow() throws {
        let preview = ProfileBadgePreview(badges: try badges(8), totalCount: 20)
        XCTAssertEqual(preview.badges.map(\.id), Array(1...7))
        XCTAssertEqual(preview.totalCount, 20)
        XCTAssertEqual(preview.remainingCount, 13)
        XCTAssertTrue(preview.hasMore)
    }

    func testPinnedLastBadgeIsNotDroppedForAnOverflowArrow() throws {
        let preview = ProfileBadgePreview(badges: try badges(8, lastPinned: true), totalCount: 20)
        XCTAssertEqual(preview.badges.map(\.id), Array(1...8))
        XCTAssertEqual(preview.badges.last?.isShowcased, true)
        XCTAssertEqual(preview.remainingCount, 12)
    }

    func testCompleteListsAreNeverArtificiallyTruncatedToSevenOrEleven() throws {
        for count in [3, 7, 8, 11, 12] {
            let preview = ProfileBadgePreview(badges: try badges(count), totalCount: count)
            XCTAssertEqual(preview.badges.count, count)
            XCTAssertEqual(preview.remainingCount, 0)
            XCTAssertFalse(preview.hasMore)
        }
    }

    func testPartialRowKeepsAllLoadedBadgesBeforeOverflow() throws {
        for count in [3, 7, 11] {
            let preview = ProfileBadgePreview(badges: try badges(count), totalCount: 35)
            XCTAssertEqual(preview.badges.count, count)
            XCTAssertEqual(preview.remainingCount, 35 - count)
        }
    }

    func testCategoryFullRowUsesConditionalOverflowInsteadOfAFixedPrefix() throws {
        let preview = ProfileBadgePreview(badges: try badges(12), totalCount: 33)
        XCTAssertEqual(preview.badges.count, 11)
        XCTAssertEqual(preview.remainingCount, 22)
        let pinned = ProfileBadgePreview(badges: try badges(12, lastPinned: true), totalCount: 33)
        XCTAssertEqual(pinned.badges.count, 12)
        XCTAssertEqual(pinned.remainingCount, 21)
    }

    func testUnknownOrStaleTotalCannotInventOverflowOrHideLoadedBadges() throws {
        for total in [nil, -1, 0, 3] as [Int?] {
            let preview = ProfileBadgePreview(badges: try badges(8), totalCount: total)
            XCTAssertEqual(preview.totalCount, 8)
            XCTAssertEqual(preview.badges.count, 8)
            XCTAssertFalse(preview.hasMore)
        }
    }

    func testPositiveTotalWithoutPreviewStillOffersTheFullList() {
        let pending = ProfileBadgePreview(badges: [], totalCount: 35)
        XCTAssertFalse(pending.isEmpty)
        XCTAssertTrue(pending.hasMore)
        XCTAssertEqual(pending.remainingCount, 35)
        XCTAssertTrue(ProfileBadgePreview(badges: [], totalCount: nil).isEmpty)
    }

    func testDuplicateAndInvalidIDsDoNotBecomeDuplicateGridIdentities() throws {
        let source = try decode([Badge].self, #"[{"id":2},{"id":0},{"id":1},{"id":2},{"id":-1}]"#)
        let preview = ProfileBadgePreview(badges: source, totalCount: nil)
        XCTAssertEqual(preview.badges.map(\.id), [2, 1])
        XCTAssertFalse(preview.hasMore)
    }

    func testRecentQueryIsBoundedDeduplicatedOwnerCSVNotJSON() {
        XCTAssertEqual(ProfileBadgePresentation.recentQuery([1, 2, 2, 0, -1, 3, 4, 5]), "1,2,3,4")
        XCTAssertEqual(ProfileBadgePresentation.recentQuery([]), "")
    }

    func testFreshRecentObjectsFollowLocalIDOrderWithSelectedBadgeFirst() throws {
        let response = try decode(ProfileBadgeSectionsResponse.self, #"{"code":0,"profile":{"id":42,"badge":{"id":5}},"recent":[{"id":1,"name":"fresh one"},{"id":2,"name":"old duplicate"},{"id":3,"name":"fresh three"},{"id":2,"name":"fresh two"},{"id":6,"name":"not locally recent"}],"sections":[{"id":1,"content":[{"id":5,"name":"selected from category"}]}],"showcased":[{"id":3}]}"#)
        let recent = ProfileBadgePresentation.recent(previousIDs: [2, 4, 3, 1, 6], response: response)
        XCTAssertEqual(recent.map(\.id), [5, 2, 3, 1])
        XCTAssertEqual(recent.map(\.name), ["selected from category", "fresh two", "fresh three", "fresh one"])
        XCTAssertEqual(recent.map(\.isSelected), [true, false, false, false])
        XCTAssertEqual(recent.map(\.isShowcased), [false, false, true, false])
    }

    func testEmptyFreshRecentDropsMissingEntriesButRetainsSelectedBadge() throws {
        let response = try decode(ProfileBadgeSectionsResponse.self,
                                  #"{"code":0,"profile":{"id":42,"badge":{"id":7}},"recent":[],"sections":[],"showcased":[]}"#)
        XCTAssertEqual(ProfileBadgePresentation.recent(previousIDs: [1, 2], response: response).map(\.id), [7])
    }

    func testPinSelectedAndRarityRemainIndependent() throws {
        let response = try decode(ProfileBadgeSectionsResponse.self,
                                  #"{"profile":{"id":42,"badge_id":2},"showcased":[{"id":1}]}"#)
        let first = ProfileBadgePresentation.decorated(try decode(Badge.self,
            #"{"id":1,"rarity":"COMMON","is_selected":true,"is_showcased":false}"#), in: response)
        let second = ProfileBadgePresentation.decorated(try decode(Badge.self,
            #"{"id":2,"rarity":"LEGENDARY","is_showcased":true}"#), in: response)
        XCTAssertEqual(first.isShowcased, true)
        XCTAssertEqual(first.isSelected, false)
        XCTAssertEqual(first.rarity, "COMMON")
        XCTAssertEqual(second.isShowcased, false)
        XCTAssertEqual(second.isSelected, true)
        XCTAssertEqual(second.rarity, "LEGENDARY")
    }

    func testAbsentShowcaseListPreservesServerMarkerButExplicitEmptyListClearsIt() throws {
        let badge = try decode(Badge.self, #"{"id":1,"is_showcased":true}"#)
        let omitted = try decode(ProfileBadgeSectionsResponse.self, #"{"code":0,"sections":[]}"#)
        let empty = try decode(ProfileBadgeSectionsResponse.self, #"{"code":0,"showcased":[],"sections":[]}"#)
        XCTAssertEqual(ProfileBadgePresentation.decorated(badge, in: omitted).isShowcased, true)
        XCTAssertEqual(ProfileBadgePresentation.decorated(badge, in: empty).isShowcased, false)
    }

    func testPartialShowcaseEntryRetainsCategoryArtworkAndExplicitOwnership() throws {
        let response = try decode(ProfileBadgeSectionsResponse.self,
            #"{"profile":{"id":42,"badge_id":7},"showcased":[{"id":7}],"sections":[{"id":1,"content":[{"id":7,"name":"loaded","type":1,"image_medium_url":"https://badges.invalid/7.json","is_owned":false}]}]}"#)
        let fallback = try decode(Badge.self, #"{"id":7,"name":"stale","is_owned":true}"#)
        let badge = ProfileBadgePresentation.resolved(fallback, in: response)
        XCTAssertEqual(badge.name, "loaded")
        XCTAssertEqual(badge.artworkURL?.lastPathComponent, "7.json")
        XCTAssertTrue(badge.isAnimated)
        XCTAssertEqual(badge.isOwned, false)
        XCTAssertEqual(badge.isShowcased, true)
        XCTAssertEqual(badge.isSelected, true)
    }

    func testFlatNicknameBadgeFieldsDoNotImplyShowcasePinning() throws {
        let profile = try decode(Profile.self,
            #"{"id":42,"badge_id":7,"badge_name":"Installed","badge_type":1,"badge_url":"https://badges.invalid/7.json"}"#)
        let badge = try XCTUnwrap(profile.selectedBadge)
        XCTAssertEqual(badge.id, 7)
        XCTAssertEqual(badge.name, "Installed")
        XCTAssertEqual(badge.isSelected, true)
        XCTAssertNil(badge.isShowcased)
        XCTAssertTrue(badge.isAnimated)
        XCTAssertEqual(badge.artworkURL?.lastPathComponent, "7.json")
    }

    func testInstalledBadgeIsAnArtworkSourceForPartialPinsAndRecentEntries() throws {
        let response = try decode(ProfileBadgeSectionsResponse.self,
            #"{"code":0,"profile":{"id":42,"badge_id":7,"badge_type":1,"badge_name":"Installed","badge_url":"https://badges.invalid/7.json"},"showcased":[{"id":7}],"recent":[{"id":7}],"sections":[]}"#)
        let partial = try decode(Badge.self, #"{"id":7}"#)
        let pin = ProfileBadgePresentation.resolved(partial, in: response)
        XCTAssertEqual(pin.name, "Installed")
        XCTAssertTrue(pin.isAnimated)
        XCTAssertEqual(pin.artworkURL?.lastPathComponent, "7.json")
        XCTAssertEqual(pin.isShowcased, true)
        let recent = try XCTUnwrap(ProfileBadgePresentation.recent(previousIDs: [7], response: response).first)
        XCTAssertEqual(recent.name, "Installed")
        XCTAssertTrue(recent.isAnimated)
        XCTAssertEqual(recent.artworkURL?.lastPathComponent, "7.json")
    }

    func testRecentHydrationKeepsLatestExplicitFieldsFromDuplicateEntries() throws {
        let response = try decode(ProfileBadgeSectionsResponse.self,
            #"{"code":0,"recent":[{"id":7,"name":"Old","is_owned":true},{"id":7,"name":"Fresh","is_owned":false}],"sections":[{"id":1,"content":[{"id":7,"image_medium_url":"https://badges.invalid/7.png","is_owned":true}]}]}"#)
        let recent = try XCTUnwrap(ProfileBadgePresentation.recent(previousIDs: [7], response: response).first)
        XCTAssertEqual(recent.name, "Fresh")
        XCTAssertEqual(recent.isOwned, false)
        XCTAssertEqual(recent.artworkURL?.lastPathComponent, "7.png")
    }

    func testNestedBadgeCannotBorrowFlatArtworkFromAnotherID() throws {
        let profile = try decode(Profile.self,
            #"{"id":42,"badge":{"id":7},"badge_id":8,"badge_type":1,"badge_name":"Other","badge_url":"https://badges.invalid/8.json"}"#)
        let badge = try XCTUnwrap(profile.selectedBadge)
        XCTAssertEqual(badge.id, 7)
        XCTAssertNil(badge.name)
        XCTAssertNil(badge.type)
        XCTAssertNil(badge.artworkURL)
    }

    func testInvalidNestedBadgeDoesNotMaskAValidFlatNicknameBadge() throws {
        let profile = try decode(Profile.self,
            #"{"id":42,"badge":{"id":0},"badge_id":7,"badge_type":1,"badge_name":"Installed","badge_url":"https://badges.invalid/7.json"}"#)
        let badge = try XCTUnwrap(profile.selectedBadge)
        XCTAssertEqual(badge.id, 7)
        XCTAssertEqual(badge.name, "Installed")
        XCTAssertTrue(badge.isAnimated)
    }

    func testBadgeTypeSelectsLottieRegardlessOfFileExtension() throws {
        for type in [1, 2, -1] {
            XCTAssertTrue(try decode(Badge.self, "{\"id\":1,\"type\":\(type)}").isAnimated)
        }
        XCTAssertFalse(try decode(Badge.self, #"{"id":1,"type":0}"#).isAnimated)
        XCTAssertFalse(try decode(Badge.self, #"{"id":1}"#).isAnimated)
        XCTAssertNil(try decode(Badge.self, #"{"id":1,"image_url":"file:///private/badge.json"}"#).artworkURL)
        XCTAssertNil(try decode(Badge.self, #"{"id":1,"image_url":"javascript:alert(1)"}"#).artworkURL)
    }

    func testMissingOrInvalidMediumArtworkFallsBackToTheOriginalURL() throws {
        for medium in ["", "badge.json", "file:///private/badge.json"] {
            let badge = try decode(Badge.self,
                "{\"id\":1,\"image_medium_url\":\"\(medium)\",\"image_url\":\"https://badges.invalid/original.json\"}")
            XCTAssertEqual(badge.artworkURL?.lastPathComponent, "original.json")
        }
    }
}
