import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class ProfileBadgesTests: XCTestCase {
    private func path(for action: ProfileBadgesModel.Action, id: Int = 7) -> String {
        switch action {
        case .select: return "/profile/preference/badge/edit/\(id)"
        case .remove: return "/profile/preference/badge/remove"
        case .pin: return "/profile/preference/badge/showcase/pin/\(id)"
        case .unpin: return "/profile/preference/badge/showcase/unpin/\(id)"
        }
    }

    private func sections(showcased: [Int] = [], selected: Int? = nil) -> String {
        let badges = showcased.map { "{\"id\":\($0),\"is_owned\":true}" }.joined(separator: ",")
        let badge = selected.map { ",\"badge\":{\"id\":\($0),\"is_owned\":true}" } ?? ""
        return "{\"code\":0,\"profile\":{\"id\":42\(badge)},\"showcased\":[\(badges)],\"sections\":[]}"
    }

    @MainActor
    func testEveryBadgeActionRequiresExplicitSuccessfulAcknowledgement() async throws {
        let suite = "ProfileBadgesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let badge = try profileTestDecode(Badge.self, #"{"id":7,"is_owned":true}"#)
        for action in [ProfileBadgesModel.Action.select, .remove, .pin, .unpin] {
            for json in ["{}", #"{"code":null}"#, #"{"code":2}"#] {
                let rig = ProfileTestRig()
                try await rig.signIn()
                let account = try XCTUnwrap(rig.session.accountKey)
                let model = ProfileBadgesModel(defaults: defaults)
                let before = try profileTestDecode(ProfileBadgeSectionsResponse.self, sections(showcased: [7], selected: 7))
                model.resource.adopt(before)
                ProfileRecentBadges.record(3, profileID: 42, defaults: defaults)
                let recent = ProfileRecentBadges.query(profileID: 42, defaults: defaults)
                let revision = rig.session.profileRevision
                rig.api.enqueue(path(for: action), json: json)
                let confirmed = await model.apply(action, to: badge, account: account, session: rig.session)
                XCTAssertFalse(confirmed, "\(action): \(json)")
                XCTAssertFalse(model.isSaving)
                XCTAssertNotNil(model.errorMessage)
                XCTAssertEqual(model.response, before)
                XCTAssertEqual(ProfileRecentBadges.query(profileID: 42, defaults: defaults), recent)
                XCTAssertEqual(rig.session.profileRevision, revision)
                XCTAssertTrue(rig.api.requests(to: "/profile/42/badge/list").isEmpty)
                XCTAssertTrue(rig.api.requests(to: "/profile/42").isEmpty)
            }
        }
    }

    @MainActor
    func testSuccessfulBadgeActionsReloadSectionsAndOwningProfile() async throws {
        let suite = "ProfileBadgesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let badge = try profileTestDecode(Badge.self, #"{"id":7,"is_owned":true}"#)
        for action in [ProfileBadgesModel.Action.select, .remove, .pin, .unpin] {
            defaults.removePersistentDomain(forName: suite)
            let rig = ProfileTestRig()
            try await rig.signIn()
            let account = try XCTUnwrap(rig.session.accountKey)
            let model = ProfileBadgesModel(defaults: defaults)
            model.resource.adopt(try profileTestDecode(ProfileBadgeSectionsResponse.self, sections(showcased: [1])))
            for id in [1, 2, 3, 4] { ProfileRecentBadges.record(id, profileID: 42, defaults: defaults) }
            let expectedRecent = action == .select ? "[7,4,3,2]" : "[4,3,2,1]"
            let updated = sections(showcased: action == .pin ? [1, 7] : [1], selected: action == .select ? 7 : nil)
            rig.api.enqueue(path(for: action), json: #"{"code":0}"#)
            rig.api.enqueue("/profile/42/badge/list", json: updated)
            rig.api.enqueue("/profile/42", json: #"{"code":0,"profile":{"id":42,"login":"updated"}}"#)
            let confirmed = await model.apply(action, to: badge, account: account, session: rig.session)
            XCTAssertTrue(confirmed)
            XCTAssertFalse(model.isSaving)
            XCTAssertNil(model.errorMessage)
            XCTAssertNil(model.resource.errorMessage)
            XCTAssertEqual(model.response, try profileTestDecode(ProfileBadgeSectionsResponse.self, updated))
            XCTAssertEqual(ProfileRecentBadges.query(profileID: 42, defaults: defaults), expectedRecent)
            XCTAssertEqual(rig.session.profile?.login, "updated")
            let request = try XCTUnwrap(rig.api.requests(to: "/profile/42/badge/list").first)
            let components = try XCTUnwrap(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "recent" })?.value, expectedRecent)
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "token" })?.value, "test-token")
        }
    }

    @MainActor
    func testFourthShowcaseBadgeIsRejectedBeforeSendingAnyRequest() async throws {
        let suite = "ProfileBadgesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let model = ProfileBadgesModel(defaults: defaults)
        model.resource.adopt(try profileTestDecode(ProfileBadgeSectionsResponse.self, sections(showcased: [1, 2, 3])))
        let badge = try profileTestDecode(Badge.self, #"{"id":7,"is_owned":true}"#)
        let before = rig.api.requests.count
        let confirmed = await model.apply(.pin, to: badge, account: account, session: rig.session)
        XCTAssertFalse(confirmed)
        XCTAssertFalse(model.isSaving)
        XCTAssertEqual(model.showcased.map(\.id), [1, 2, 3])
        XCTAssertEqual(model.errorMessage, "Можно закрепить не более трёх значков. Сначала открепите один из них.")
        XCTAssertEqual(rig.api.requests.count, before)
    }

    @MainActor
    func testAlreadyShowcasedBadgeDoesNotCountAsAFourthBadge() async throws {
        let suite = "ProfileBadgesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let model = ProfileBadgesModel(defaults: defaults)
        let json = sections(showcased: [1, 2, 3])
        model.resource.adopt(try profileTestDecode(ProfileBadgeSectionsResponse.self, json))
        let badge = try profileTestDecode(Badge.self, #"{"id":3,"is_owned":true}"#)
        rig.api.enqueue(path(for: .pin, id: 3), json: #"{"code":0}"#)
        rig.api.enqueue("/profile/42/badge/list", json: json)
        let confirmed = await model.apply(.pin, to: badge, account: account, session: rig.session)
        XCTAssertTrue(confirmed)
        XCTAssertEqual(model.showcased.map(\.id), [1, 2, 3])
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testConcurrentBadgeActionIsIgnoredUntilFirstActionCompletes() async throws {
        let suite = "ProfileBadgesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let model = ProfileBadgesModel(defaults: defaults)
        let badge = try profileTestDecode(Badge.self, #"{"id":7,"is_owned":true}"#)
        let held = rig.api.hold(path(for: .select))
        defer { held.respond("{}", status: 500) }
        let first = Task { await model.apply(.select, to: badge, account: account, session: rig.session) }
        defer { first.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        XCTAssertTrue(model.isSaving)
        let second = await model.apply(.remove, to: badge, account: account, session: rig.session)
        XCTAssertFalse(second)
        XCTAssertTrue(rig.api.requests(to: path(for: .remove)).isEmpty)
        rig.api.enqueue("/profile/42/badge/list", json: sections(selected: 7))
        held.respond(#"{"code":0}"#)
        let confirmed = await first.value
        XCTAssertTrue(confirmed)
        XCTAssertFalse(model.isSaving)
        XCTAssertEqual(ProfileRecentBadges.query(profileID: 42, defaults: defaults), "[7]")
    }

    @MainActor
    func testLateSelectionCannotUpdateRecentBadgesAfterSessionChange() async throws {
        let suite = "ProfileBadgesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let badge = try profileTestDecode(Badge.self, #"{"id":7,"is_owned":true}"#)
        for profileID in [42, 43] {
            let rig = ProfileTestRig()
            try await rig.signIn(token: "previous")
            let account = try XCTUnwrap(rig.session.accountKey)
            let model = ProfileBadgesModel(defaults: defaults)
            let held = rig.api.hold(path(for: .select))
            defer { held.respond("{}", status: 500) }
            let mutation = Task { await model.apply(.select, to: badge, account: account, session: rig.session) }
            defer { mutation.cancel() }
            await fulfillment(of: [held.arrived], timeout: 5)
            try await rig.signIn(profileID: profileID, token: "current")
            let revision = rig.session.profileRevision
            held.respond(#"{"code":0,"badge":{"id":7}}"#)
            let confirmed = await mutation.value
            XCTAssertFalse(confirmed)
            XCTAssertNil(model.errorMessage)
            XCTAssertNil(model.response)
            XCTAssertNil(ProfileRecentBadges.query(profileID: 42, defaults: defaults))
            XCTAssertEqual(rig.session.profileRevision, revision)
            XCTAssertTrue(rig.api.requests(to: "/profile/42/badge/list").isEmpty)
        }
    }

    @MainActor
    func testCancelledSelectionDoesNotRecordRecentBadgesOrRefreshProfile() async throws {
        let suite = "ProfileBadgesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let model = ProfileBadgesModel(defaults: defaults)
        let badge = try profileTestDecode(Badge.self, #"{"id":7,"is_owned":true}"#)
        let held = rig.api.hold(path(for: .select))
        defer { held.respond("{}", status: 500) }
        let mutation = Task { await model.apply(.select, to: badge, account: account, session: rig.session) }
        defer { mutation.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        mutation.cancel()
        let confirmed = await mutation.value
        await fulfillment(of: [held.cancelled], timeout: 5)
        XCTAssertFalse(confirmed)
        XCTAssertFalse(model.isSaving)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(ProfileRecentBadges.query(profileID: 42, defaults: defaults))
        XCTAssertTrue(rig.api.requests(to: "/profile/42/badge/list").isEmpty)
        XCTAssertTrue(rig.api.requests(to: "/profile/42").isEmpty)
    }

    @MainActor
    func testCancelledPostSaveRefreshDoesNotDismissButKeepsConfirmedRecentBadge() async throws {
        let suite = "ProfileBadgesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let model = ProfileBadgesModel(defaults: defaults)
        let badge = try profileTestDecode(Badge.self, #"{"id":7,"is_owned":true}"#)
        rig.api.enqueue(path(for: .select), json: #"{"code":0}"#)
        let held = rig.api.hold("/profile/42/badge/list")
        defer { held.respond("{}", status: 500) }
        let mutation = Task { await model.apply(.select, to: badge, account: account, session: rig.session) }
        defer { mutation.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        mutation.cancel()
        let confirmed = await mutation.value
        await fulfillment(of: [held.cancelled], timeout: 5)
        XCTAssertFalse(confirmed)
        XCTAssertFalse(model.isSaving)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.resource.errorMessage)
        XCTAssertEqual(ProfileRecentBadges.query(profileID: 42, defaults: defaults), "[7]")
        XCTAssertTrue(rig.api.requests(to: "/profile/42").isEmpty)
    }

    @MainActor
    func testFailedPostSaveRefreshKeepsConfirmedRecentBadgeAndExposesReloadError() async throws {
        let suite = "ProfileBadgesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let model = ProfileBadgesModel(defaults: defaults)
        let before = try profileTestDecode(ProfileBadgeSectionsResponse.self, sections(selected: 3))
        model.resource.adopt(before)
        let badge = try profileTestDecode(Badge.self, #"{"id":7,"is_owned":true}"#)
        rig.api.enqueue(path(for: .select), json: #"{"code":0}"#)
        rig.api.enqueue("/profile/42/badge/list", json: "{}", status: 503)
        rig.api.enqueue("/profile/42", json: #"{"code":0,"profile":{"id":42,"badge":{"id":7}}}"#)

        let confirmed = await model.apply(.select, to: badge, account: account, session: rig.session)

        XCTAssertTrue(confirmed, "A failed reload must not undo the acknowledged selection")
        XCTAssertFalse(model.isSaving)
        XCTAssertNil(model.errorMessage)
        XCTAssertNotNil(model.resource.errorMessage)
        XCTAssertEqual(model.response, before)
        XCTAssertEqual(ProfileRecentBadges.query(profileID: 42, defaults: defaults), "[7]")
        XCTAssertEqual(rig.session.profile?.badge?.id, 7)

        rig.api.enqueue("/profile/42/badge/list", json: sections(selected: 7))
        await model.load(profileID: 42, session: rig.session, viewer: account.viewerKey)
        XCTAssertNil(model.resource.errorMessage)
        XCTAssertEqual(model.selectedID, 7)
        XCTAssertEqual(ProfileRecentBadges.query(profileID: 42, defaults: defaults), "[7]")
    }
}
