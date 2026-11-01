import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class ProfileAuditRegressionTests: XCTestCase {
    private let newNotification = #"{"code":0,"content":[{"id":1,"type":"friend","is_new":true,"by_profile":{"id":71}}],"total_count":1,"total_page_count":1}"#

    @MainActor
    private func signedInRig() async throws -> ProfileTestRig {
        let rig = ProfileTestRig()
        rig.api.enqueue("/notification/count", json: #"{"code":0,"count":9}"#)
        try await rig.signIn()
        return rig
    }

    @MainActor
    func testFailedAndMalformedNotificationLoadsDoNotMarkRead() async throws {
        for response in [#"{"code":2}"#, "{}"] {
            let rig = try await signedInRig()
            rig.api.enqueue("/notification/all/0", json: response)
            let model = NotificationsModel()
            await model.load(session: rig.session)
            await model.markReadIfNeeded(session: rig.session, delayed: false)
            XCTAssertTrue(rig.api.requests(to: "/notification/read").isEmpty)
            XCTAssertEqual(rig.session.unreadNotifications, 9)
            XCTAssertNotNil(model.paginator?.errorMessage)
        }
    }

    @MainActor
    func testReadFailureKeepsBadgeAndNewRowsUntilAnAcknowledgedRetry() async throws {
        let rig = try await signedInRig()
        rig.api.enqueue("/notification/all/0", json: newNotification)
        rig.api.enqueue("/notification/read", json: #"{"code":2}"#)
        let model = NotificationsModel()
        await model.load(session: rig.session)
        await model.markReadIfNeeded(session: rig.session, delayed: false)
        XCTAssertEqual(rig.session.unreadNotifications, 9)
        XCTAssertTrue(model.paginator?.items.first?.base.isNew == true)
        XCTAssertNotNil(model.readError)
        rig.api.enqueue("/notification/read", json: #"{"code":0}"#)
        await model.retryRead(session: rig.session)
        XCTAssertEqual(rig.session.unreadNotifications, 0)
        XCTAssertFalse(model.paginator?.items.first?.base.isNew ?? true)
        XCTAssertNil(model.readError)
    }

    @MainActor
    func testEmptyLoadedFeedDoesNotClearAnUnrelatedUnreadBadge() async throws {
        let rig = try await signedInRig()
        rig.api.enqueue("/notification/all/0", json: #"{"code":0,"content":[],"total_count":0,"total_page_count":0}"#)
        let model = NotificationsModel()
        await model.load(session: rig.session)
        await model.markReadIfNeeded(session: rig.session, delayed: false)
        XCTAssertTrue(rig.api.requests(to: "/notification/read").isEmpty)
        XCTAssertEqual(rig.session.unreadNotifications, 9)
    }

    @MainActor
    func testDelayedReadCannotClearAnotherAccountsBadge() async throws {
        let rig = try await signedInRig()
        rig.api.enqueue("/notification/all/0", json: newNotification)
        let held = rig.api.hold("/notification/read")
        defer { held.respond("{}", status: 500) }
        let model = NotificationsModel()
        await model.load(session: rig.session)
        let read = Task { await model.markReadIfNeeded(session: rig.session, delayed: false) }
        defer { read.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        rig.api.enqueue("/notification/count", json: #"{"code":0,"count":7}"#)
        try await rig.signIn(profileID: 43, token: "another-token")
        model.invalidate(for: rig.session.viewerKey)
        held.respond(#"{"code":0}"#)
        await read.value
        XCTAssertEqual(rig.session.unreadNotifications, 7)
        XCTAssertNil(model.paginator)
    }

    @MainActor
    func testForeignFriendsListDoesNotLoadOwnRequestsOrRecommendations() async throws {
        let rig = try await signedInRig()
        rig.api.enqueue("/profile/friend/all/71/0", json: #"{"code":0,"content":[],"total_page_count":0}"#)
        let model = ProfileFriendsModel(ownerID: 71, viewer: rig.session.viewerKey, session: rig.session)
        await model.load()
        XCTAssertFalse(model.ownsList)
        XCTAssertTrue(rig.api.requests(to: "/profile/friend/recommendations").isEmpty)
        XCTAssertTrue(rig.api.requests(to: "/profile/friend/requests/in/0").isEmpty)
        XCTAssertTrue(rig.api.requests(to: "/profile/friend/requests/out/0").isEmpty)
    }

    @MainActor
    func testIncomingHideUsesHideRatherThanRemove() async throws {
        let rig = try await signedInRig()
        let model = ProfileFriendsModel(ownerID: 42, viewer: rig.session.viewerKey, session: rig.session)
        let empty = #"{"code":0,"content":[],"total_page_count":0}"#
        for path in ["/profile/friend/all/42/0", "/profile/friend/requests/in/0", "/profile/friend/requests/out/0", "/profile/friend/recommendations"] {
            rig.api.enqueue(path, json: empty)
            rig.api.enqueue(path, json: empty)
        }
        await model.load()
        rig.api.enqueue("/profile/friend/request/hide/71", json: #"{"code":0}"#)
        let profile = try profileTestDecode(Profile.self, #"{"id":71,"friend_status":"PENDING_SECOND_FIRST"}"#)
        await model.change(profile, action: .hide)
        XCTAssertEqual(rig.api.requests(to: "/profile/friend/request/hide/71").count, 1)
        XCTAssertTrue(rig.api.requests(to: "/profile/friend/request/remove/71").isEmpty)
    }

    @MainActor
    func testBareArrayPaginationContinuesUntilAnEmptyPage() async throws {
        let first = try profileTestDecode(Profile.self, #"{"id":1}"#)
        let second = try profileTestDecode(Profile.self, #"{"id":2}"#)
        let list = Paginator<Profile>(continuesWithoutPageCount: true) { page in
            PageableResponse(content: page == 0 ? [first] : page == 1 ? [second] : [], currentPage: page)
        }
        await list.loadFirstPageIfNeeded()
        XCTAssertTrue(list.hasMore)
        await list.loadNextPage()
        XCTAssertEqual(list.items.map(\.id), [1, 2])
        await list.loadNextPage()
        XCTAssertFalse(list.hasMore)
    }

    @MainActor
    func testPrivacyClampsPinnedSectionAndFriendResponseDoesNotReplaceOtherFields() throws {
        let model = ProfileViewModel()
        model.adopt(try profileTestDecode(Profile.self, #"{"id":71,"login":"kept","is_counts_hidden":true,"pinned_section_id":3}"#))
        XCTAssertEqual(model.section, .statistics)
        model.applyFriendStatus(.friend, profileID: 71)
        XCTAssertEqual(model.profile?.login, "kept")
        XCTAssertEqual(model.profile?.friendStatus, .friend)
        model.applyFriendStatus(nil, profileID: 99)
        XCTAssertEqual(model.profile?.friendStatus, .friend)
        model.applyBlockState(true, profileID: 71)
        XCTAssertTrue(model.profile?.isBlocked == true)
        XCTAssertNil(model.profile?.friendStatus)
    }

    @MainActor
    func testAvatarGifValidationAndWatchTimeFormats() throws {
        XCTAssertTrue(ProfileImagePreparation.isValidAvatarGIF(try ProfileThemeTestImages.gif(frameCount: 2)))
        XCTAssertFalse(ProfileImagePreparation.isValidAvatarGIF(try ProfileThemeTestImages.png()))
        XCTAssertFalse(ProfileImagePreparation.isValidAvatarGIF(Data(count: ProfileEditorRules.avatarAnimationByteLimit + 1)))
        XCTAssertEqual(ProfileWatchTimeFormat.daysAndHours.text(seconds: 21 * 86_400 + 7 * 3_600), "~ 21 день 7 часов")
        XCTAssertEqual(ProfileWatchTimeFormat.hours.text(seconds: 2 * 3_600), "~ 2 часа")
    }
}
