import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class ProfileRecentBadgesTests: XCTestCase {
    private let fresh = #"{"code":0,"profile":{"id":42,"badge":{"id":5,"name":"selected"}},"recent":[{"id":1,"name":"fresh one"},{"id":2,"name":"fresh two"},{"id":3,"name":"fresh three"}],"showcased":[{"id":3}],"sections":[]}"#

    private func query(_ request: URLRequest, _ name: String) -> String? {
        request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == name }?.value
    }

    @MainActor
    func testLegacyIDsAreSanitizedAndSentAsCSV() throws {
        let suite = "ProfileRecentBadgesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([1, 2, 2, 0, -1, 3, 4, 5], forKey: "profile.42.recentBadgeIDs")
        XCTAssertEqual(ProfileRecentBadges.query(profileID: 42, defaults: defaults), "1,2,3,4")
        XCTAssertTrue(ProfileRecentBadges.badges(profileID: 42, defaults: defaults).isEmpty)
        XCTAssertNil(defaults.data(forKey: "profile.42.recentBadges"), "Reading legacy IDs must not fabricate badge objects")
    }

    @MainActor
    func testSuccessfulOwnerLoadRefreshesObjectsAndPutsSelectedBadgeFirst() async throws {
        let suite = "ProfileRecentBadgesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let old = try profileTestDecode(Badge.self, #"{"id":2,"name":"stale two"}"#)
        ProfileRecentBadges.record(old, profileID: 42, defaults: defaults)
        defaults.set([2, 4, 3, 1], forKey: "profile.42.recentBadgeIDs")
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = ProfileBadgesModel(defaults: defaults)
        rig.api.enqueue("/profile/42/badge/list", json: fresh)
        await model.load(profileID: 42, session: rig.session, viewer: rig.session.viewerKey)
        let request = try XCTUnwrap(rig.api.requests(to: "/profile/42/badge/list").first)
        XCTAssertEqual(query(request, "recent"), "2,4,3,1")
        XCTAssertEqual(ProfileRecentBadges.query(profileID: 42, defaults: defaults), "5,2,3,1")
        let cached = ProfileRecentBadges.badges(profileID: 42, defaults: defaults)
        XCTAssertEqual(cached.map(\.id), [5, 2, 3, 1])
        XCTAssertEqual(cached.map(\.name), ["selected", "fresh two", "fresh three", "fresh one"])
        XCTAssertEqual(cached.map(\.isSelected), [true, false, false, false])
        XCTAssertEqual(cached.map(\.isShowcased), [false, false, true, false])
        XCTAssertEqual(model.response?.recent, cached)
        XCTAssertTrue(model.canEdit)
    }

    @MainActor
    func testForeignReadSendsEmptyRecentAndCannotReadOrReplaceFormerAccountsCache() async throws {
        let suite = "ProfileRecentBadgesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let badge = try profileTestDecode(Badge.self, #"{"id":7,"name":"private recent"}"#)
        ProfileRecentBadges.record(badge, profileID: 42, defaults: defaults)
        let before = defaults.data(forKey: "profile.42.recentBadges")
        let rig = ProfileTestRig()
        try await rig.signIn(profileID: 43)
        let model = ProfileBadgesModel(defaults: defaults)
        rig.api.enqueue("/profile/42/badge/list", json: fresh)
        await model.load(profileID: 42, session: rig.session, viewer: rig.session.viewerKey)
        let request = try XCTUnwrap(rig.api.requests(to: "/profile/42/badge/list").first)
        XCTAssertEqual(query(request, "recent"), "")
        XCTAssertEqual(model.response?.recent, [])
        XCTAssertFalse(model.canEdit)
        XCTAssertEqual(model.showcased.map(\.id), [3], "Public pins are not owner-gated")
        XCTAssertEqual(defaults.data(forKey: "profile.42.recentBadges"), before)
        XCTAssertEqual(ProfileRecentBadges.query(profileID: 42, defaults: defaults), "7")
        XCTAssertEqual(ProfileRecentBadges.query(profileID: 43, defaults: defaults), "")
    }

    @MainActor
    func testGuestReadAlsoSuppressesRecentWithoutChangingCache() async throws {
        let suite = "ProfileRecentBadgesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        ProfileRecentBadges.record(7, profileID: 42, defaults: defaults)
        let rig = ProfileTestRig()
        await rig.session.restore()
        let model = ProfileBadgesModel(defaults: defaults)
        rig.api.enqueue("/profile/42/badge/list", json: fresh)
        await model.load(profileID: 42, session: rig.session, viewer: rig.session.viewerKey)
        XCTAssertEqual(query(try XCTUnwrap(rig.api.requests(to: "/profile/42/badge/list").first), "recent"), "")
        XCTAssertEqual(model.response?.recent, [])
        XCTAssertEqual(ProfileRecentBadges.query(profileID: 42, defaults: defaults), "7")
    }

    @MainActor
    func testSupersededOwnerLoadCannotRestoreStaleObjectsOrSelection() async throws {
        let suite = "ProfileRecentBadgesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([1, 2, 3], forKey: "profile.42.recentBadgeIDs")
        let rig = ProfileTestRig()
        try await rig.signIn()
        let viewer = rig.session.viewerKey
        let model = ProfileBadgesModel(defaults: defaults)
        let held = rig.api.hold("/profile/42/badge/list")
        defer { held.respond("{}", status: 500) }
        let old = Task { await model.load(profileID: 42, session: rig.session, viewer: viewer) }
        defer { old.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        rig.api.enqueue("/profile/42/badge/list", json: fresh)
        await model.load(profileID: 42, session: rig.session, viewer: viewer)
        held.respond(#"{"code":0,"profile":{"id":42,"badge":{"id":9}},"recent":[{"id":1,"name":"stale one"}],"sections":[]}"#)
        await old.value
        XCTAssertEqual(model.selectedID, 5)
        XCTAssertEqual(ProfileRecentBadges.query(profileID: 42, defaults: defaults), "5,1,2,3")
        XCTAssertEqual(ProfileRecentBadges.badges(profileID: 42, defaults: defaults).first { $0.id == 1 }?.name, "fresh one")
    }

    @MainActor
    func testCancelledOwnerLoadDoesNotClearOrRewriteHistory() async throws {
        let suite = "ProfileRecentBadgesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        ProfileRecentBadges.record(7, profileID: 42, defaults: defaults)
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = ProfileBadgesModel(defaults: defaults)
        let viewer = rig.session.viewerKey
        let held = rig.api.hold("/profile/42/badge/list")
        defer { held.respond("{}", status: 500) }
        let load = Task { await model.load(profileID: 42, session: rig.session, viewer: viewer) }
        defer { load.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        load.cancel()
        await load.value
        await fulfillment(of: [held.cancelled], timeout: 5)
        XCTAssertEqual(ProfileRecentBadges.query(profileID: 42, defaults: defaults), "7")
        XCTAssertNil(model.response)
        XCTAssertNil(model.resource.errorMessage)
    }

    @MainActor
    func testLateOwnerResponseCannotPublishAfterSessionReplacement() async throws {
        for newID in [42, 43] {
            let suite = "ProfileRecentBadgesTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            ProfileRecentBadges.record(7, profileID: 42, defaults: defaults)
            let rig = ProfileTestRig()
            try await rig.signIn(token: "previous")
            let viewer = rig.session.viewerKey
            let model = ProfileBadgesModel(defaults: defaults)
            let held = rig.api.hold("/profile/42/badge/list")
            defer { held.respond("{}", status: 500) }
            let load = Task { await model.load(profileID: 42, session: rig.session, viewer: viewer) }
            defer { load.cancel() }
            await fulfillment(of: [held.arrived], timeout: 5)
            try await rig.signIn(profileID: newID, token: "current")
            held.respond(fresh)
            await load.value
            XCTAssertNil(model.response)
            XCTAssertEqual(ProfileRecentBadges.query(profileID: 42, defaults: defaults), "7")
        }
    }

    @MainActor
    func testWrongOwnerAndMissingListAreErrorsNotEmptyHistory() async throws {
        for json in [#"{"code":0,"profile":{"id":71},"recent":[],"sections":[]}"#, #"{"code":0}"#,
                     #"{"code":0,"total_count":35}"#] {
            let suite = "ProfileRecentBadgesTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            ProfileRecentBadges.record(7, profileID: 42, defaults: defaults)
            let rig = ProfileTestRig()
            try await rig.signIn()
            let model = ProfileBadgesModel(defaults: defaults)
            rig.api.enqueue("/profile/42/badge/list", json: json)
            await model.load(profileID: 42, session: rig.session, viewer: rig.session.viewerKey)
            XCTAssertNil(model.response)
            XCTAssertNotNil(model.resource.errorMessage)
            XCTAssertFalse(model.canEdit)
            XCTAssertEqual(ProfileRecentBadges.query(profileID: 42, defaults: defaults), "7")
        }
    }

    @MainActor
    func testOmittedRecentDoesNotDiscardLegacyIDsWhileExplicitEmptyDoes() throws {
        let suite = "ProfileRecentBadgesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([1, 2, 3], forKey: "profile.42.recentBadgeIDs")
        let omitted = try profileTestDecode(ProfileBadgeSectionsResponse.self,
                                           #"{"code":0,"profile":{"id":42,"badge":{"id":7}},"sections":[]}"#)
        XCTAssertEqual(ProfileRecentBadges.refresh(omitted, profileID: 42, defaults: defaults).map(\.id), [7])
        XCTAssertEqual(ProfileRecentBadges.query(profileID: 42, defaults: defaults), "7,1,2,3")
        let empty = try profileTestDecode(ProfileBadgeSectionsResponse.self,
                                         #"{"code":0,"profile":{"id":42},"recent":[],"sections":[]}"#)
        XCTAssertEqual(ProfileRecentBadges.refresh(empty, profileID: 42, defaults: defaults), [])
        XCTAssertEqual(ProfileRecentBadges.query(profileID: 42, defaults: defaults), "")
    }

    @MainActor
    func testOmittedRecentRefreshesKnownObjectsWithoutDroppingLegacyIDs() throws {
        let suite = "ProfileRecentBadgesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        ProfileRecentBadges.record(try profileTestDecode(Badge.self,
            #"{"id":7,"name":"Old","image_url":"https://badges.invalid/old.png","is_owned":true}"#), profileID: 42, defaults: defaults)
        defaults.set([7, 8], forKey: "profile.42.recentBadgeIDs")
        let response = try profileTestDecode(ProfileBadgeSectionsResponse.self,
            #"{"code":0,"profile":{"id":42,"badge":{"id":7}},"showcased":[],"sections":[{"id":1,"content":[{"id":7,"name":"Fresh","type":1,"image_url":"https://badges.invalid/fresh.json","is_owned":false}]}]}"#)
        let recent = ProfileRecentBadges.refresh(response, profileID: 42, defaults: defaults)
        XCTAssertEqual(recent.map(\.id), [7])
        XCTAssertEqual(recent.first?.name, "Fresh")
        XCTAssertEqual(recent.first?.isOwned, false)
        XCTAssertEqual(recent.first?.isAnimated, true)
        XCTAssertEqual(recent.first?.artworkURL?.lastPathComponent, "fresh.json")
        XCTAssertEqual(ProfileRecentBadges.query(profileID: 42, defaults: defaults), "7,8")
    }
}
