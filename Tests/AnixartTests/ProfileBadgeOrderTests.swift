import Foundation
import XCTest
import AnixartKit
@testable import Anixart

/// Reserved .invalid transport only. These tests never reorder a live account.
final class ProfileBadgeOrderTests: XCTestCase {
    private let path = "/profile/preference/badge/showcase/reorder"

    private func snapshot(_ ids: [Int], profileID: Int = 42) -> String {
        let badges = ids.map { "{\"id\":\($0)}" }.joined(separator: ",")
        return "{\"code\":0,\"profile\":{\"id\":\(profileID)},\"showcased\":[\(badges)],\"sections\":[]}"
    }

    @MainActor
    private func loaded(_ rig: ProfileTestRig, ids: [Int] = [1, 2, 3]) async throws -> ProfileBadgeOrderModel {
        let account = try XCTUnwrap(rig.session.accountKey)
        rig.api.enqueue("/profile/42/badge/list", json: snapshot(ids))
        let model = ProfileBadgeOrderModel()
        await model.load(profileID: 42, account: account, session: rig.session)
        XCTAssertNil(model.resource.errorMessage)
        return model
    }

    @MainActor
    func testOpeningMovingAndCancellingAreReadOnlyAndUnchangedSaveIsIgnored() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let model = try await loaded(rig)
        let request = try XCTUnwrap(rig.api.requests(to: "/profile/42/badge/list").first)
        let components = try XCTUnwrap(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        XCTAssertEqual(components.queryItems?.first { $0.name == "recent" }?.value, "")
        model.move(id: 3, by: -1)
        XCTAssertEqual(model.badges.map(\.id), [1, 3, 2])
        XCTAssertTrue(model.canSave)
        model.cancelChanges()
        XCTAssertEqual(model.badges.map(\.id), [1, 2, 3])
        XCTAssertFalse(model.hasChanges)
        let confirmed = await model.save(profileID: 42, account: account, session: rig.session)
        XCTAssertFalse(confirmed)
        XCTAssertTrue(rig.api.requests(to: path).isEmpty)
        XCTAssertTrue(rig.api.requests(to: "/profile/42").isEmpty)
    }

    @MainActor
    func testPartialPinsRetainArtworkFromTheirCategoryAndInstalledBadge() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        rig.api.enqueue("/profile/42/badge/list", json:
            #"{"code":0,"profile":{"id":42,"badge":{"id":2,"name":"Installed","type":1,"image_url":"https://badges.invalid/2.json"}},"showcased":[{"id":1},{"id":2}],"sections":[{"id":1,"content":[{"id":1,"name":"Category","image_medium_url":"https://badges.invalid/1.png"}]}]}"#)
        let model = ProfileBadgeOrderModel()
        await model.load(profileID: 42, account: account, session: rig.session)
        XCTAssertEqual(model.badges.map(\.name), ["Category", "Installed"])
        XCTAssertEqual(model.badges.map { $0.artworkURL?.lastPathComponent }, ["1.png", "2.json"])
        XCTAssertEqual(model.badges.map(\.isShowcased), [true, true])
        XCTAssertEqual(model.badges.map(\.isSelected), [false, true])
    }

    @MainActor
    func testMalformedUnacknowledgedForeignAndOverLimitOrdersAreNotEditable() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let invalid = ["{}", #"{"profile":{"id":42},"showcased":[]}"#,
                       #"{"code":null,"profile":{"id":42},"showcased":[]}"#,
                       #"{"code":0,"profile":{"id":42},"sections":[]}"#,
                       snapshot([1, 2], profileID: 71), snapshot([1, 1]), snapshot([0, 2]),
                       snapshot([-1, 2]), snapshot([1, 2, 3, 4])]
        for json in invalid {
            let model = ProfileBadgeOrderModel()
            rig.api.enqueue("/profile/42/badge/list", json: json)
            await model.load(profileID: 42, account: account, session: rig.session)
            XCTAssertNil(model.resource.value, json)
            XCTAssertNotNil(model.resource.errorMessage, json)
            XCTAssertTrue(model.badges.isEmpty, json)
            XCTAssertFalse(model.canReorder, json)
            let confirmed = await model.save(profileID: 42, account: account, session: rig.session)
            XCTAssertFalse(confirmed, json)
        }
        XCTAssertTrue(rig.api.requests(to: path).isEmpty)
    }

    @MainActor
    func testExplicitEmptyAndOnePinAreValidReadsButCannotBeReordered() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        for ids in [[], [1]] {
            let model = try await loaded(rig, ids: ids)
            XCTAssertEqual(model.badges.map(\.id), ids)
            XCTAssertFalse(model.canReorder)
            XCTAssertFalse(model.canSave)
        }
    }

    @MainActor
    func testAbsentProfileDoesNotRejectAnOtherwiseValidAccountScopedRead() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        rig.api.enqueue("/profile/42/badge/list", json: #"{"code":0,"showcased":[{"id":1},{"id":2}]}"#)
        let model = ProfileBadgeOrderModel()
        await model.load(profileID: 42, account: account, session: rig.session)
        XCTAssertTrue(model.canReorder)
        XCTAssertFalse(model.canSave)
        XCTAssertNil(model.resource.errorMessage)
    }

    @MainActor
    func testInvalidMoveRangesAndUnsupportedOffsetsDoNotChangeTheDraft() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = try await loaded(rig)
        model.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        model.move(fromOffsets: IndexSet(integer: 0), toOffset: -1)
        model.move(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        model.move(id: 1, by: -1)
        model.move(id: 3, by: 1)
        model.move(id: 1, by: 2)
        model.move(id: 99, by: -1)
        XCTAssertEqual(model.badges.map(\.id), [1, 2, 3])
        model.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(model.badges.map(\.id), [2, 3, 1])
        XCTAssertEqual(model.originalIDs, [1, 2, 3])
    }

    @MainActor
    func testFailedOrMissingAcknowledgementRetainsDraftAndDoesNotRefreshProfile() async throws {
        for json in ["{}", #"{"code":null}"#, #"{"code":2}"#] {
            let rig = ProfileTestRig()
            try await rig.signIn()
            let account = try XCTUnwrap(rig.session.accountKey)
            let model = try await loaded(rig, ids: [1, 2])
            model.move(id: 2, by: -1)
            rig.api.enqueue(path, json: json)
            let revision = rig.session.profileRevision
            let confirmed = await model.save(profileID: 42, account: account, session: rig.session)
            XCTAssertFalse(confirmed)
            XCTAssertEqual(model.badges.map(\.id), [2, 1])
            XCTAssertEqual(model.originalIDs, [1, 2])
            XCTAssertTrue(model.canSave)
            XCTAssertNotNil(model.errorMessage)
            XCTAssertEqual(rig.session.profileRevision, revision)
            XCTAssertTrue(rig.api.requests(to: "/profile/42").isEmpty)
        }
    }

    @MainActor
    func testSaveSendsOnlyThePinnedPermutationAndAcknowledgesItOnce() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let model = try await loaded(rig)
        model.move(id: 3, by: -1)
        rig.api.enqueue(path, json: #"{"code":0}"#)
        let confirmed = await model.save(profileID: 42, account: account, session: rig.session)
        XCTAssertTrue(confirmed)
        let request = try XCTUnwrap(rig.api.requests(to: path).first)
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["ids"] as? [Int], [1, 3, 2])
        XCTAssertEqual(model.originalIDs, [1, 3, 2])
        XCTAssertEqual(model.resource.value?.showcased?.map(\.id), [1, 3, 2])
        XCTAssertFalse(model.canSave)
        let again = await model.save(profileID: 42, account: account, session: rig.session)
        XCTAssertFalse(again)
        XCTAssertEqual(rig.api.requests(to: path).count, 1)
        XCTAssertEqual(rig.api.requests(to: "/profile/42").count, 1)
    }

    @MainActor
    func testPendingSaveIgnoresAdditionalMovesCancelAndSecondSave() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let model = try await loaded(rig, ids: [1, 2])
        model.move(id: 2, by: -1)
        let held = rig.api.hold(path)
        defer { held.respond("{}", status: 500) }
        let first = Task { await model.save(profileID: 42, account: account, session: rig.session) }
        defer { first.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        model.move(id: 1, by: -1)
        model.cancelChanges()
        let second = await model.save(profileID: 42, account: account, session: rig.session)
        XCTAssertFalse(second)
        XCTAssertEqual(model.badges.map(\.id), [2, 1])
        held.respond(#"{"code":0}"#)
        let confirmed = await first.value
        XCTAssertTrue(confirmed)
        XCTAssertEqual(rig.api.requests(to: path).count, 1)
        XCTAssertFalse(model.isSaving)
    }

    @MainActor
    func testCancelledSaveBeforeAcknowledgementKeepsUnconfirmedDraft() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let model = try await loaded(rig, ids: [1, 2])
        model.move(id: 2, by: -1)
        let held = rig.api.hold(path)
        defer { held.respond("{}", status: 500) }
        let save = Task { await model.save(profileID: 42, account: account, session: rig.session) }
        defer { save.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        save.cancel()
        let confirmed = await save.value
        await fulfillment(of: [held.cancelled], timeout: 5)
        XCTAssertFalse(confirmed)
        XCTAssertTrue(model.canSave)
        XCTAssertEqual(model.originalIDs, [1, 2])
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(rig.api.requests(to: "/profile/42").isEmpty)
    }

    @MainActor
    func testCancelledRefreshAfterAcknowledgementCannotResubmitTheSameOrder() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let model = try await loaded(rig, ids: [1, 2])
        model.move(id: 2, by: -1)
        rig.api.enqueue(path, json: #"{"code":0}"#)
        let held = rig.api.hold("/profile/42")
        defer { held.respond("{}", status: 500) }
        let save = Task { await model.save(profileID: 42, account: account, session: rig.session) }
        defer { save.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        XCTAssertEqual(model.originalIDs, [2, 1])
        save.cancel()
        let confirmed = await save.value
        await fulfillment(of: [held.cancelled], timeout: 5)
        XCTAssertFalse(confirmed, "Do not dismiss a route from a cancelled task")
        XCTAssertFalse(model.canSave, "The server has already acknowledged this order")
        XCTAssertNil(model.errorMessage)
        let again = await model.save(profileID: 42, account: account, session: rig.session)
        XCTAssertFalse(again)
        XCTAssertEqual(rig.api.requests(to: path).count, 1)
    }

    @MainActor
    func testWrongTargetAndReplacementLoginCannotBorrowTheLoadedAccount() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "previous")
        let previous = try XCTUnwrap(rig.session.accountKey)
        let model = try await loaded(rig, ids: [1, 2])
        model.move(id: 2, by: -1)
        let foreign = await model.save(profileID: 71, account: previous, session: rig.session)
        XCTAssertFalse(foreign)
        try await rig.signIn(token: "current")
        let current = try XCTUnwrap(rig.session.accountKey)
        let old = await model.save(profileID: 42, account: previous, session: rig.session)
        let borrowed = await model.save(profileID: 42, account: current, session: rig.session)
        XCTAssertFalse(old)
        XCTAssertFalse(borrowed)
        XCTAssertTrue(rig.api.requests(to: path).isEmpty)
    }

    @MainActor
    func testLateSaveCannotPublishAfterAccountChangeAndReset() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let model = try await loaded(rig, ids: [1, 2])
        model.move(id: 2, by: -1)
        let held = rig.api.hold(path)
        defer { held.respond("{}", status: 500) }
        let save = Task { await model.save(profileID: 42, account: account, session: rig.session) }
        defer { save.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        try await rig.signIn(profileID: 43, token: "another-account")
        model.reset()
        held.respond(#"{"code":0}"#)
        let confirmed = await save.value
        XCTAssertFalse(confirmed)
        XCTAssertTrue(model.badges.isEmpty)
        XCTAssertTrue(model.originalIDs.isEmpty)
        XCTAssertNil(model.resource.value)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(rig.api.requests(to: "/profile/42").isEmpty)
    }

    @MainActor
    func testSupersededLoadCannotRestoreAnOlderPinnedOrder() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let model = ProfileBadgeOrderModel()
        let held = rig.api.hold("/profile/42/badge/list")
        defer { held.respond("{}", status: 500) }
        let old = Task { await model.load(profileID: 42, account: account, session: rig.session) }
        defer { old.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        rig.api.enqueue("/profile/42/badge/list", json: snapshot([2, 3]))
        await model.load(profileID: 42, account: account, session: rig.session)
        held.respond(snapshot([1, 2]))
        await old.value
        XCTAssertEqual(model.badges.map(\.id), [2, 3])
        XCTAssertEqual(model.originalIDs, [2, 3])
        XCTAssertNil(model.resource.errorMessage)
    }
}
