import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class ProfileDeletionTests: XCTestCase {
    @MainActor
    private func signedInModel(_ rig: ProfileTestRig, status: String = #"{"code":3}"#) async throws -> ProfileDeletionViewModel {
        try await rig.signIn()
        let model = ProfileDeletionViewModel(account: rig.session.accountKey, session: rig.session)
        rig.api.enqueue("/profile/deletion/status", json: status)
        await model.load()
        return model
    }

    @MainActor
    func testCodeZeroWithNoDatesIsStillAnActiveDeletionRequest() async throws {
        let rig = ProfileTestRig()
        let model = try await signedInModel(rig, status: #"{"code":0,"requested_at":null,"delete_at":null}"#)
        XCTAssertTrue(model.hasRequest)
        XCTAssertTrue(model.mayChange)
        XCTAssertNil(model.resource.value?.deleteAt)
        let requested = await model.request(password: "test")
        XCTAssertFalse(requested)
        XCTAssertTrue(rig.api.requests(to: "/profile/deletion/request").isEmpty)
    }

    @MainActor
    func testUnknownEmptyStatusBlocksAllMutations() async throws {
        let rig = ProfileTestRig()
        let model = try await signedInModel(rig, status: "{}")
        XCTAssertNil(model.resource.value)
        XCTAssertNotNil(model.resource.errorMessage)
        XCTAssertFalse(model.mayChange)
        let requested = await model.request(password: "test")
        let cancelled = await model.cancel()
        XCTAssertFalse(requested)
        XCTAssertFalse(cancelled)
        XCTAssertTrue(rig.api.requests(to: "/profile/deletion/request").isEmpty)
        XCTAssertTrue(rig.api.requests(to: "/profile/deletion/cancel").isEmpty)
    }

    @MainActor
    func testRefreshingStatusBlocksActionsUsingPreviouslyLoadedStatus() async throws {
        let rig = ProfileTestRig()
        let model = try await signedInModel(rig, status: #"{"code":0}"#)
        let held = rig.api.hold("/profile/deletion/status")
        defer { held.respond("{}", status: 500) }
        let refresh = Task { await model.load() }
        defer { refresh.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        XCTAssertFalse(model.mayChange)
        let cancelled = await model.cancel()
        XCTAssertFalse(cancelled)
        XCTAssertTrue(rig.api.requests(to: "/profile/deletion/cancel").isEmpty)
        held.respond(#"{"code":3}"#)
        await refresh.value
        XCTAssertFalse(model.hasRequest)
        XCTAssertTrue(model.mayChange)
    }

    @MainActor
    func testFailedStatusRefreshDoesNotAllowActionsWithOldStatus() async throws {
        let rig = ProfileTestRig()
        let model = try await signedInModel(rig, status: #"{"code":0}"#)
        rig.api.enqueue("/profile/deletion/status", json: "{}", status: 503)
        await model.load()
        XCTAssertTrue(model.hasRequest)
        XCTAssertNotNil(model.resource.errorMessage)
        XCTAssertFalse(model.mayChange)
        let cancelled = await model.cancel()
        XCTAssertFalse(cancelled)
    }

    @MainActor
    func testCancelledStatusRefreshRequiresSuccessfulReloadBeforeAnyAction() async throws {
        for status in [#"{"code":0}"#, #"{"code":3}"#] {
            let rig = ProfileTestRig()
            let model = try await signedInModel(rig, status: status)
            let hadRequest = model.hasRequest
            let held = rig.api.hold("/profile/deletion/status")
            defer { held.respond("{}", status: 500) }
            let refresh = Task { await model.load() }
            defer { refresh.cancel() }
            await fulfillment(of: [held.arrived], timeout: 5)
            refresh.cancel()
            await refresh.value
            await fulfillment(of: [held.cancelled], timeout: 5)

            XCTAssertEqual(model.hasRequest, hadRequest)
            XCTAssertFalse(model.resource.isLoading)
            XCTAssertNil(model.resource.errorMessage)
            XCTAssertFalse(model.mayChange)
            let requested = await model.request(password: "test")
            let cancelled = await model.cancel()
            XCTAssertFalse(requested)
            XCTAssertFalse(cancelled)
            XCTAssertTrue(rig.api.requests(to: "/profile/deletion/request").isEmpty)
            XCTAssertTrue(rig.api.requests(to: "/profile/deletion/cancel").isEmpty)

            rig.api.enqueue("/profile/deletion/status", json: status)
            await model.load()
            XCTAssertTrue(model.mayChange)
            XCTAssertEqual(model.hasRequest, hadRequest)
        }
    }

    @MainActor
    func testRequestAcknowledgementIsNotAdoptedAsStatusAndWaitsForConfirmation() async throws {
        let rig = ProfileTestRig()
        let model = try await signedInModel(rig)
        rig.api.enqueue("/profile/deletion/request", json: #"{"code":0}"#)
        let status = rig.api.hold("/profile/deletion/status")
        defer { status.respond("{}", status: 500) }
        let request = Task { await model.request(password: "test-password") }
        defer { request.cancel() }
        await fulfillment(of: [status.arrived], timeout: 5)
        XCTAssertTrue(model.isSaving)
        XCTAssertNil(model.resource.value)
        XCTAssertNil(model.notice)
        XCTAssertFalse(model.mayChange)
        status.respond(#"{"code":0}"#)
        let confirmed = await request.value
        XCTAssertTrue(confirmed)
        XCTAssertTrue(model.hasRequest)
        XCTAssertEqual(model.notice, "Запрос на удаление создан.")
        XCTAssertEqual(rig.api.requests(to: "/profile/deletion/status").count, 2)
        let sent = try XCTUnwrap(rig.api.requests(to: "/profile/deletion/request").first?.httpBody)
        XCTAssertEqual(String(data: sent, encoding: .utf8), "password=test-password")
    }

    @MainActor
    func testCancellationAcknowledgementReloadsCodeThreeBeforeSuccessNotice() async throws {
        let rig = ProfileTestRig()
        let model = try await signedInModel(rig, status: #"{"code":0}"#)
        rig.api.enqueue("/profile/deletion/cancel", json: #"{"code":0}"#)
        rig.api.enqueue("/profile/deletion/status", json: #"{"code":3}"#)
        let cancelled = await model.cancel()
        XCTAssertTrue(cancelled)
        XCTAssertFalse(model.hasRequest)
        XCTAssertEqual(model.notice, "Запрос на удаление отменён.")
        XCTAssertEqual(rig.api.requests(to: "/profile/deletion/status").count, 2)
    }

    @MainActor
    func testMismatchedFinalStatusDoesNotReportRequestOrCancellationSuccess() async throws {
        for requesting in [true, false] {
            let rig = ProfileTestRig()
            let model = try await signedInModel(rig, status: requesting ? #"{"code":3}"# : #"{"code":0}"#)
            let path = requesting ? "/profile/deletion/request" : "/profile/deletion/cancel"
            rig.api.enqueue(path, json: #"{"code":0}"#)
            rig.api.enqueue("/profile/deletion/status", json: requesting ? #"{"code":3}"# : #"{"code":0}"#)
            let confirmed: Bool
            if requesting { confirmed = await model.request(password: "test") }
            else { confirmed = await model.cancel() }
            XCTAssertFalse(confirmed)
            XCTAssertNil(model.notice)
            XCTAssertNotNil(model.errorMessage)
            XCTAssertEqual(model.hasRequest, !requesting)
            XCTAssertFalse(model.mayChange)
            let retry: Bool
            if requesting { retry = await model.request(password: "test") }
            else { retry = await model.cancel() }
            XCTAssertFalse(retry)
            XCTAssertEqual(rig.api.requests(to: path).count, 1)

            rig.api.enqueue("/profile/deletion/status", json: requesting ? #"{"code":3}"# : #"{"code":0}"#)
            await model.load()
            XCTAssertTrue(model.mayChange)
            XCTAssertNil(model.errorMessage)
        }
    }

    @MainActor
    func testUnconfirmedMutationResponseKeepsStatusAndDoesNotReloadIt() async throws {
        for json in ["{}", #"{"code":3}"#, #"{"code":2}"#] {
            let rig = ProfileTestRig()
            let model = try await signedInModel(rig)
            rig.api.enqueue("/profile/deletion/request", json: json)
            let requested = await model.request(password: "test")
            XCTAssertFalse(requested)
            XCTAssertNil(model.notice)
            XCTAssertNotNil(model.errorMessage)
            XCTAssertEqual(model.resource.value?.hasDeletionRequest, false)
            XCTAssertEqual(rig.api.requests(to: "/profile/deletion/status").count, 1)
            XCTAssertFalse(model.mayChange)
            let retry = await model.request(password: "test")
            XCTAssertFalse(retry)
            XCTAssertEqual(rig.api.requests(to: "/profile/deletion/request").count, 1)
        }
    }

    @MainActor
    func testCancelledMutationKeepsOldDisplayButRequiresFreshStatus() async throws {
        for requesting in [true, false] {
            let rig = ProfileTestRig()
            let model = try await signedInModel(rig, status: requesting ? #"{"code":3}"# : #"{"code":0}"#)
            let path = requesting ? "/profile/deletion/request" : "/profile/deletion/cancel"
            let held = rig.api.hold(path)
            defer { held.respond("{}", status: 500) }
            let mutation = Task {
                if requesting { return await model.request(password: "test") }
                return await model.cancel()
            }
            defer { mutation.cancel() }
            await fulfillment(of: [held.arrived], timeout: 5)
            mutation.cancel()
            let confirmed = await mutation.value
            await fulfillment(of: [held.cancelled], timeout: 5)

            XCTAssertFalse(confirmed)
            XCTAssertFalse(model.isSaving)
            XCTAssertFalse(model.mayChange)
            XCTAssertEqual(model.hasRequest, !requesting)
            XCTAssertNil(model.notice)
            XCTAssertNil(model.errorMessage)
            XCTAssertEqual(rig.api.requests(to: "/profile/deletion/status").count, 1)
            let retry: Bool
            if requesting { retry = await model.request(password: "test") }
            else { retry = await model.cancel() }
            XCTAssertFalse(retry)
            XCTAssertEqual(rig.api.requests(to: path).count, 1)

            // The server may have changed the status before cancellation reached
            // the transport. Only a new read is authoritative.
            rig.api.enqueue("/profile/deletion/status", json: requesting ? #"{"code":0}"# : #"{"code":3}"#)
            await model.load()
            XCTAssertTrue(model.mayChange)
            XCTAssertEqual(model.hasRequest, requesting)
        }
    }

    @MainActor
    func testCancelledConfirmationCannotReportSuccessOrUnlockActions() async throws {
        for requesting in [true, false] {
            let rig = ProfileTestRig()
            let model = try await signedInModel(rig, status: requesting ? #"{"code":3}"# : #"{"code":0}"#)
            let path = requesting ? "/profile/deletion/request" : "/profile/deletion/cancel"
            rig.api.enqueue(path, json: #"{"code":0}"#)
            let held = rig.api.hold("/profile/deletion/status")
            defer { held.respond("{}", status: 500) }
            let mutation = Task {
                if requesting { return await model.request(password: "test") }
                return await model.cancel()
            }
            defer { mutation.cancel() }
            await fulfillment(of: [held.arrived], timeout: 5)
            mutation.cancel()
            let confirmed = await mutation.value
            await fulfillment(of: [held.cancelled], timeout: 5)

            XCTAssertFalse(confirmed)
            XCTAssertFalse(model.isSaving)
            XCTAssertFalse(model.mayChange)
            XCTAssertNil(model.resource.value)
            XCTAssertNil(model.notice)
            XCTAssertNil(model.errorMessage)
            XCTAssertNil(model.resource.errorMessage)

            rig.api.enqueue("/profile/deletion/status", json: requesting ? #"{"code":0}"# : #"{"code":3}"#)
            await model.load()
            XCTAssertTrue(model.mayChange)
            XCTAssertEqual(model.hasRequest, requesting)
        }
    }

    @MainActor
    func testManualRefreshCannotSupersedeMutationOrItsConfirmation() async throws {
        let rig = ProfileTestRig()
        let model = try await signedInModel(rig)
        let acknowledgement = rig.api.hold("/profile/deletion/request")
        let status = rig.api.hold("/profile/deletion/status")
        defer { acknowledgement.respond("{}", status: 500); status.respond("{}", status: 500) }
        let mutation = Task { await model.request(password: "test") }
        defer { mutation.cancel() }
        await fulfillment(of: [acknowledgement.arrived], timeout: 5)
        await model.load()
        XCTAssertTrue(model.isSaving)
        XCTAssertEqual(model.resource.value?.hasDeletionRequest, false)
        XCTAssertEqual(rig.api.requests(to: "/profile/deletion/status").count, 1)

        acknowledgement.respond(#"{"code":0}"#)
        await fulfillment(of: [status.arrived], timeout: 5)
        await model.load()
        XCTAssertTrue(model.resource.isLoading)
        XCTAssertNil(model.notice)
        XCTAssertEqual(rig.api.requests(to: "/profile/deletion/status").count, 2)
        status.respond(#"{"code":0}"#)
        let confirmed = await mutation.value
        XCTAssertTrue(confirmed)
        XCTAssertTrue(model.hasRequest)
        XCTAssertTrue(model.mayChange)
        XCTAssertEqual(model.notice, "Запрос на удаление создан.")
        XCTAssertEqual(rig.api.requests(to: "/profile/deletion/status").count, 2)
    }

    @MainActor
    func testFailedFollowUpStatusRequiresReloadBeforeNextMutation() async throws {
        let rig = ProfileTestRig()
        let model = try await signedInModel(rig)
        rig.api.enqueue("/profile/deletion/request", json: #"{"code":0}"#)
        rig.api.enqueue("/profile/deletion/status", json: "{}", status: 503)
        let confirmed = await model.request(password: "test")
        XCTAssertFalse(confirmed)
        XCTAssertFalse(model.mayChange)
        XCTAssertNil(model.notice)
        XCTAssertNotNil(model.resource.errorMessage)
        rig.api.enqueue("/profile/deletion/status", json: #"{"code":0}"#)
        await model.load()
        XCTAssertTrue(model.mayChange)
        XCTAssertTrue(model.hasRequest)
        XCTAssertNil(model.notice)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testLateDeletionAcknowledgementCannotReloadOrPublishForAnotherSession() async throws {
        let rig = ProfileTestRig()
        let model = try await signedInModel(rig)
        let held = rig.api.hold("/profile/deletion/request")
        defer { held.respond("{}", status: 500) }
        let request = Task { await model.request(password: "test") }
        defer { request.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        try await rig.signIn(token: "new-session")
        model.invalidate(for: rig.session.accountKey)
        held.respond(#"{"code":0}"#)
        let confirmed = await request.value
        XCTAssertFalse(confirmed)
        XCTAssertFalse(model.mayChange)
        XCTAssertNil(model.resource.value)
        XCTAssertNil(model.notice)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(rig.api.requests(to: "/profile/deletion/status").count, 1)
    }
}
