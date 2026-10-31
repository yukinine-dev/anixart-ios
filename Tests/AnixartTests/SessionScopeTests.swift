import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class SessionScopeTests: XCTestCase {
    @MainActor
    private func assertCancelled<Value: Sendable>(_ task: Task<Value, Error>, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await task.value; XCTFail("Expected cancellation", file: file, line: line) }
        catch { XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)", file: file, line: line) }
    }

    @MainActor
    func testRestoreWithoutCredentialsStaysGuest() async {
        let store = ProfileControlledTokenStore()
        let rig = ProfileTestRig(store: store)
        await rig.session.restore()
        XCTAssertEqual(rig.session.state, .guest)
        XCTAssertNil(rig.session.accountKey)
        XCTAssertNil(rig.session.profile)
        XCTAssertTrue(rig.api.requests.isEmpty)
    }

    @MainActor
    func testRestoreLoadsOnlyTheStoredOwningProfile() async {
        let store = ProfileControlledTokenStore(token: "stored", profileID: 42)
        let rig = ProfileTestRig(store: store)
        rig.api.enqueue("/profile/42", json: #"{"code":0,"profile":{"id":42,"login":"restored"}}"#)
        await rig.session.restore()
        XCTAssertEqual(rig.session.currentProfileID, 42)
        XCTAssertEqual(rig.session.profile?.login, "restored")
        let request = rig.api.requests(to: "/profile/42").first
        XCTAssertTrue(request?.url?.query?.contains("token=stored") == true)
    }

    @MainActor
    func testSigningIntoTheSameProfileCreatesANewViewerRevision() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "first")
        let oldViewer = rig.session.viewerKey
        try await rig.signIn(token: "second")
        XCTAssertEqual(rig.session.currentProfileID, 42)
        XCTAssertNotEqual(oldViewer, rig.session.viewerKey)
        XCTAssertNotEqual(oldViewer.account, rig.session.accountKey)
        let requests = rig.api.requests.count
        let stale = Task { try await rig.session.sendViewerRequest(ProfileEndpoints.profile(id: 42), for: oldViewer) }
        defer { stale.cancel() }
        await assertCancelled(stale)
        XCTAssertEqual(rig.api.requests.count, requests)
    }

    @MainActor
    func testSignedInPublicValidationStaysTokenFreeWithoutStoreReads() async throws {
        let store = ProfileControlledTokenStore()
        let rig = ProfileTestRig(store: store)
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let before = await store.tokenReads
        rig.api.enqueue("/auth/checkLogin", json: #"{"code":0}"#)
        _ = try await rig.session.sendAccountRequest(AuthEndpoints.checkLogin("example"), for: account)
        let after = await store.tokenReads
        XCTAssertEqual(after, before)
        let request = try XCTUnwrap(rig.api.requests(to: "/auth/checkLogin").first)
        XCTAssertFalse(request.url?.query?.contains("token=") == true)
    }

    @MainActor
    func testGuestReadDoesNotBorrowALaterSignInTokenOrPublishItsResponse() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let guest = rig.session.viewerKey
        let held = rig.api.hold("/profile/71")
        defer { held.respond("{}", status: 500) }
        let read = Task { try await rig.session.sendViewerRequest(ProfileEndpoints.profile(id: 71), for: guest) }
        defer { read.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        try await rig.signIn()
        held.respond(#"{"code":0,"profile":{"id":71}}"#)
        await assertCancelled(read)
        XCTAssertFalse(held.request?.url?.query?.contains("token=") == true)
    }

    @MainActor
    func testLateBusinessErrorFromOldAccountBecomesCancellation() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let held = rig.api.hold("/profile/preference/my")
        defer { held.respond("{}", status: 500) }
        let read = Task { try await rig.session.sendAccountRequest(ProfilePreferenceEndpoints.my(), for: account) }
        defer { read.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        await rig.session.signOut()
        held.respond(#"{"code":2}"#)
        await assertCancelled(read)
        XCTAssertNil(rig.session.profile)
    }

    @MainActor
    func testDelayedLoginCannotUndoSignOut() async {
        let store = ProfileControlledTokenStore()
        let rig = ProfileTestRig(store: store)
        let held = rig.api.hold("/auth/signIn")
        defer { held.respond("{}", status: 500) }
        let login = Task { try await rig.session.signIn(login: "test", password: "test") }
        defer { login.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        await rig.session.signOut()
        held.respond(ProfileTestAPI.signInJSON(profileID: 42, token: "stale"))
        await assertCancelled(login)
        let writes = await store.writes
        XCTAssertEqual(writes, [.clear])
        XCTAssertEqual(rig.session.state, .guest)
    }

    @MainActor
    func testOlderLoginResponseCannotReplaceANewerLogin() async throws {
        let store = ProfileControlledTokenStore()
        let rig = ProfileTestRig(store: store)
        let held = rig.api.hold("/auth/signIn")
        defer { held.respond("{}", status: 500) }
        let first = Task { try await rig.session.signIn(login: "first", password: "test") }
        defer { first.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        try await rig.signIn(profileID: 43, token: "newer")
        held.respond(ProfileTestAPI.signInJSON(profileID: 42, token: "older"))
        await assertCancelled(first)
        let writes = await store.writes
        XCTAssertEqual(writes, [.save("newer", 43)])
        XCTAssertEqual(rig.session.currentProfileID, 43)
    }

    @MainActor
    func testCancelledLoginDuringSaveRollsBackGuestCredentialsBeforePublishing() async throws {
        let store = ProfileControlledTokenStore()
        let rig = ProfileTestRig(store: store)
        let gate = await store.pauseNext(.save)
        defer { gate.release() }
        let login = Task { try await rig.signIn(token: "cancelled") }
        defer { login.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        XCTAssertEqual(rig.session.state, .guest)
        XCTAssertNil(rig.session.accountKey)
        login.cancel()
        gate.release()
        await assertCancelled(login)
        let token = await store.token()
        let id = await store.profileID()
        let writes = await store.writes
        XCTAssertNil(token)
        XCTAssertNil(id)
        XCTAssertEqual(writes, [.save("cancelled", 42), .clear])
        XCTAssertEqual(rig.session.state, .guest)
    }

    @MainActor
    func testCancelledAccountSwitchRestoresPreviousCredentials() async throws {
        let store = ProfileControlledTokenStore()
        let rig = ProfileTestRig(store: store)
        try await rig.signIn(token: "previous")
        let oldViewer = rig.session.viewerKey
        let gate = await store.pauseNext(.save)
        defer { gate.release() }
        let login = Task { try await rig.signIn(profileID: 43, token: "cancelled") }
        defer { login.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        XCTAssertNil(rig.session.accountKey)
        login.cancel()
        gate.release()
        await assertCancelled(login)
        let token = await store.token()
        let id = await store.profileID()
        let writes = await store.writes
        XCTAssertEqual(token, "previous")
        XCTAssertEqual(id, 42)
        XCTAssertEqual(writes, [.save("previous", 42), .save("cancelled", 43), .save("previous", 42)])
        XCTAssertEqual(rig.session.currentProfileID, 42)
        XCTAssertEqual(rig.session.profile?.id, 42)
        XCTAssertNotEqual(oldViewer, rig.session.viewerKey)
    }

    @MainActor
    func testCancelledSaveRollsBackBeforeFollowingSignOutClear() async throws {
        let store = ProfileControlledTokenStore()
        let rig = ProfileTestRig(store: store)
        let gate = await store.pauseNext(.save)
        defer { gate.release() }
        let login = Task { try await rig.signIn(token: "cancelled") }
        defer { login.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        login.cancel()
        let queued = expectation(description: "Sign-out queued")
        let logout = Task { queued.fulfill(); await rig.session.signOut() }
        defer { logout.cancel() }
        await fulfillment(of: [queued], timeout: 5)
        let before = await store.writes
        XCTAssertEqual(before, [.save("cancelled", 42)])
        gate.release()
        await assertCancelled(login)
        await logout.value
        let writes = await store.writes
        XCTAssertEqual(writes, [.save("cancelled", 42), .clear, .clear])
        let token = await store.token()
        XCTAssertNil(token)
    }

    @MainActor
    func testCancelledSaveRollsBackBeforeFollowingLoginSave() async throws {
        let store = ProfileControlledTokenStore()
        let rig = ProfileTestRig(store: store)
        let firstGate = await store.pauseNext(.save)
        defer { firstGate.release() }
        let first = Task { try await rig.signIn(token: "cancelled") }
        defer { first.cancel() }
        await fulfillment(of: [firstGate.entered], timeout: 5)
        first.cancel()
        let secondGate = await store.pauseNext(.save)
        defer { secondGate.release() }
        let second = Task { try await rig.signIn(profileID: 43, token: "current") }
        defer { second.cancel() }
        firstGate.release()
        await assertCancelled(first)
        await fulfillment(of: [secondGate.entered], timeout: 5)
        let writes = await store.writes
        XCTAssertEqual(writes, [.save("cancelled", 42), .clear, .save("current", 43)])
        secondGate.release()
        try await second.value
        let token = await store.token()
        XCTAssertEqual(token, "current")
        XCTAssertEqual(rig.session.currentProfileID, 43)
    }

    @MainActor
    func testSlowSignOutClearCannotOvertakeNextLoginSave() async throws {
        let store = ProfileControlledTokenStore()
        let rig = ProfileTestRig(store: store)
        try await rig.signIn(token: "previous")
        let gate = await store.pauseNext(.clear)
        defer { gate.release() }
        let logout = Task { await rig.session.signOut() }
        defer { logout.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        let login = Task { try await rig.signIn(profileID: 43, token: "current") }
        defer { login.cancel() }
        gate.release()
        await logout.value
        try await login.value
        let writes = await store.writes
        let token = await store.token()
        XCTAssertEqual(writes, [.save("previous", 42), .clear, .save("current", 43)])
        XCTAssertEqual(token, "current")
    }

    @MainActor
    func testPasswordResponsePersistsReplacementEvenAfterEditorCancellation() async throws {
        let store = ProfileControlledTokenStore()
        let rig = ProfileTestRig(store: store)
        try await rig.signIn(token: "old")
        let account = try XCTUnwrap(rig.session.accountKey)
        let held = rig.api.hold("/profile/preference/password/change")
        defer { held.respond("{}", status: 500) }
        let password = Task { try await rig.session.changePassword(current: "old", new: "new", for: account) }
        defer { password.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        password.cancel()
        held.respond(#"{"code":0,"token":"replacement"}"#)
        await assertCancelled(password)
        let token = await store.token()
        let writes = await store.writes
        XCTAssertEqual(token, "replacement")
        XCTAssertEqual(writes, [.save("old", 42), .replace("replacement", 42, "old")])
        XCTAssertEqual(rig.session.currentProfileID, 42)
        XCTAssertNotEqual(rig.session.accountKey, account)
        XCTAssertNotNil(rig.session.accountKey)
    }

    @MainActor
    func testCancelledPasswordProfileRefreshKeepsReplacementWithoutReportingSuccess() async throws {
        let store = ProfileControlledTokenStore()
        let rig = ProfileTestRig(store: store)
        try await rig.signIn(token: "old")
        let account = try XCTUnwrap(rig.session.accountKey)
        rig.api.enqueue("/profile/preference/password/change", json: #"{"code":0,"token":"replacement"}"#)
        let held = rig.api.hold("/profile/42")
        defer { held.respond("{}", status: 500) }
        let password = Task { try await rig.session.changePassword(current: "old", new: "new", for: account) }
        defer { password.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        password.cancel()
        await assertCancelled(password)
        await fulfillment(of: [held.cancelled], timeout: 5)

        let token = await store.token()
        let writes = await store.writes
        XCTAssertEqual(token, "replacement")
        XCTAssertEqual(writes, [.save("old", 42), .replace("replacement", 42, "old")])
        XCTAssertEqual(rig.session.currentProfileID, 42)
        XCTAssertNotEqual(rig.session.accountKey, account)
        XCTAssertNotNil(rig.session.accountKey)
    }

    @MainActor
    func testPasswordRequiresExplicitAcknowledgementBeforeReplacingToken() async throws {
        for json in ["{}", #"{"code":null}"#, #"{"token":"replacement"}"#, #"{"code":null,"token":"replacement"}"#] {
            let store = ProfileControlledTokenStore()
            let rig = ProfileTestRig(store: store)
            try await rig.signIn(token: "old")
            let account = try XCTUnwrap(rig.session.accountKey)
            rig.api.enqueue("/profile/preference/password/change", json: json)
            do {
                _ = try await rig.session.changePassword(current: "old", new: "new", for: account)
                XCTFail("An unacknowledged password change must not replace the token")
            } catch {
                XCTAssertEqual(error as? AnixartError, .decoding(message: "Сервер не подтвердил изменение", path: "profile/preference/password/change"))
            }
            let token = await store.token()
            let writes = await store.writes
            XCTAssertEqual(token, "old")
            XCTAssertEqual(writes, [.save("old", 42)])
            XCTAssertEqual(rig.session.accountKey, account)
            XCTAssertTrue(rig.api.requests(to: "/profile/42").isEmpty)
        }
    }

    @MainActor
    func testAcknowledgedPasswordChangeStillRequiresReplacementToken() async throws {
        for json in [#"{"code":0}"#, #"{"code":0,"token":""}"#] {
            let store = ProfileControlledTokenStore()
            let rig = ProfileTestRig(store: store)
            try await rig.signIn(token: "old")
            let account = try XCTUnwrap(rig.session.accountKey)
            rig.api.enqueue("/profile/preference/password/change", json: json)
            do {
                _ = try await rig.session.changePassword(current: "old", new: "new", for: account)
                XCTFail("A password change needs the server's replacement token")
            } catch {
                XCTAssertEqual(error as? AnixartError, .decoding(message: "Сервер не вернул новый токен", path: "profile/preference/password/change"))
            }
            let token = await store.token()
            let writes = await store.writes
            XCTAssertEqual(token, "old")
            XCTAssertEqual(writes, [.save("old", 42)])
            XCTAssertEqual(rig.session.accountKey, account)
        }
    }

    @MainActor
    func testLatePasswordResponseCannotOverwriteNewLoginEvenToSameProfile() async throws {
        for profileID in [42, 43] {
            let store = ProfileControlledTokenStore()
            let rig = ProfileTestRig(store: store)
            try await rig.signIn(token: "old")
            let account = try XCTUnwrap(rig.session.accountKey)
            let held = rig.api.hold("/profile/preference/password/change")
            defer { held.respond("{}", status: 500) }
            let password = Task { try await rig.session.changePassword(current: "old", new: "new", for: account) }
            defer { password.cancel() }
            await fulfillment(of: [held.arrived], timeout: 5)
            try await rig.signIn(profileID: profileID, token: "current")
            held.respond(#"{"code":0,"token":"stale-replacement"}"#)
            await assertCancelled(password)
            let token = await store.token()
            let writes = await store.writes
            XCTAssertEqual(token, "current")
            XCTAssertEqual(writes, [.save("old", 42), .save("current", profileID)])
            XCTAssertEqual(rig.session.currentProfileID, profileID)
        }
    }

    @MainActor
    func testPasswordSaveFinishesBeforeQueuedSignOutClear() async throws {
        let store = ProfileControlledTokenStore()
        let rig = ProfileTestRig(store: store)
        try await rig.signIn(token: "old")
        let account = try XCTUnwrap(rig.session.accountKey)
        let gate = await store.pauseNext(.replace)
        defer { gate.release() }
        rig.api.enqueue("/profile/preference/password/change", json: #"{"code":0,"token":"replacement"}"#)
        let password = Task { try await rig.session.changePassword(current: "old", new: "new", for: account) }
        defer { password.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        let queued = expectation(description: "Sign-out queued during password persistence")
        let logout = Task { queued.fulfill(); await rig.session.signOut() }
        defer { logout.cancel() }
        await fulfillment(of: [queued], timeout: 5)
        gate.release()
        await assertCancelled(password)
        await logout.value
        let writes = await store.writes
        let token = await store.token()
        XCTAssertEqual(writes, [.save("old", 42), .replace("replacement", 42, "old"), .clear])
        XCTAssertNil(token)
    }

    @MainActor
    func testNewProfileRefreshWinsOverDelayedOlderRefresh() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let held = rig.api.hold("/profile/42")
        defer { held.respond("{}", status: 500) }
        let first = Task { await rig.session.refreshProfile() }
        defer { first.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        rig.api.enqueue("/profile/42", json: #"{"code":0,"profile":{"id":42,"login":"new"}}"#)
        await rig.session.refreshProfile()
        let revision = rig.session.profileRevision
        held.respond(#"{"code":0,"profile":{"id":42,"login":"old"}}"#)
        await first.value
        XCTAssertEqual(rig.session.profile?.login, "new")
        XCTAssertEqual(rig.session.profileRevision, revision)
    }

    @MainActor
    func testLateNotificationCountCannotUndoBadgeClear() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let held = rig.api.hold("/notification/count")
        defer { held.respond("{}", status: 500) }
        let refresh = Task { await rig.session.refreshNotificationCount() }
        defer { refresh.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        rig.session.clearNotificationBadge()
        held.respond(#"{"code":0,"count":99}"#)
        await refresh.value
        XCTAssertEqual(rig.session.unreadNotifications, 0)
    }
}
