import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class ReleaseActionScopeTests: XCTestCase {
    @MainActor
    private func model(_ rig: ProfileTestRig, isFavorite: Bool = false, listStatus: Int? = 1) throws -> ReleaseDetailViewModel {
        let status = listStatus.map { String($0) } ?? "null"
        let release = try profileTestDecode(Release.self,
            "{\"id\":71,\"is_favorite\":\(isFavorite),\"profile_list_status\":\(status),\"your_vote\":2}")
        return ReleaseDetailViewModel(releaseID: 71, preloaded: release, session: rig.session)
    }

    private func detailResponse(isFavorite: Bool, listStatus: Int? = 1) -> String {
        let status = listStatus.map { String($0) } ?? "null"
        return "{\"code\":0,\"release\":{\"id\":71,\"is_favorite\":\(isFavorite),\"profile_list_status\":\(status),\"your_vote\":2}}"
    }

    @MainActor
    func testOlderDetailLoadCannotOverwriteOptimisticFavoriteChange() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = try model(rig)
        let detail = rig.api.hold("/release/71")
        defer { detail.respond("{}", status: 500) }
        let loading = Task { await model.load() }
        defer { loading.cancel() }
        await fulfillment(of: [detail.arrived], timeout: 5)
        let mutation = rig.api.hold("/favorite/add/71")
        defer { mutation.respond("{}", status: 500) }
        let favorite = Task { await model.toggleFavorite() }
        defer { favorite.cancel() }
        await fulfillment(of: [mutation.arrived], timeout: 5)
        XCTAssertEqual(model.release?.isFavorite, true)
        detail.respond(#"{"code":0,"release":{"id":71,"is_favorite":false}}"#)
        await loading.value
        XCTAssertEqual(model.release?.isFavorite, true)
        XCTAssertTrue(model.isPerformingAction)
        rig.api.enqueue("/release/71", json: detailResponse(isFavorite: true))
        mutation.respond(#"{"code":0}"#)
        await favorite.value
        XCTAssertEqual(rig.api.requests(to: "/profile/42").count, 1)
        XCTAssertFalse(model.isPerformingAction)
    }

    @MainActor
    func testOrdinaryLoadAndSecondActionAreBlockedDuringMutation() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = try model(rig)
        let held = rig.api.hold("/favorite/add/71")
        defer { held.respond("{}", status: 500) }
        let favorite = Task { await model.toggleFavorite() }
        defer { favorite.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        await model.load()
        await model.setList(.completed)
        await model.toggleFavorite()
        XCTAssertTrue(rig.api.requests(to: "/release/71").isEmpty)
        XCTAssertTrue(rig.api.requests(to: "/profile/list/add/3/71").isEmpty)
        XCTAssertEqual(rig.api.requests(to: "/favorite/add/71").count, 1)
        rig.api.enqueue("/release/71", json: detailResponse(isFavorite: true))
        held.respond(#"{"code":0}"#)
        await favorite.value
    }

    @MainActor
    func testFavoriteAndListErrorsRollbackTheirOwnOptimisticFields() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = try model(rig)
        rig.api.enqueue("/favorite/add/71", json: #"{"code":2}"#)
        await model.toggleFavorite()
        XCTAssertEqual(model.release?.isFavorite, false)
        XCTAssertNotNil(model.actionError)
        rig.api.enqueue("/profile/list/add/3/71", json: #"{"code":2}"#)
        await model.setList(.completed)
        XCTAssertEqual(model.release?.profileListStatus, 1)
        XCTAssertNotNil(model.actionError)
        XCTAssertFalse(model.isPerformingAction)
    }

    @MainActor
    func testFavoriteActionsRequireExplicitConfirmationBeforeRefreshingProfile() async throws {
        for wasFavorite in [false, true] {
            for json in ["{}", #"{"code":null}"#, #"{"code":2}"#] {
                let rig = ProfileTestRig()
                try await rig.signIn()
                let model = try model(rig, isFavorite: wasFavorite)
                let path = wasFavorite ? "/favorite/delete/71" : "/favorite/add/71"
                let refreshes = rig.api.requests(to: "/profile/42").count
                rig.api.enqueue(path, json: json)
                await model.toggleFavorite()
                XCTAssertEqual(model.release?.isFavorite, wasFavorite)
                XCTAssertEqual(model.release?.profileListStatus, 1)
                XCTAssertNotNil(model.actionError)
                XCTAssertFalse(model.isPerformingAction)
                XCTAssertEqual(rig.api.requests(to: path).count, 1)
                XCTAssertEqual(rig.api.requests(to: "/profile/42").count, refreshes)

                rig.api.enqueue(path, json: #"{"code":0}"#)
                rig.api.enqueue("/release/71", json: detailResponse(isFavorite: !wasFavorite))
                await model.toggleFavorite()
                XCTAssertEqual(model.release?.isFavorite, !wasFavorite)
                XCTAssertNil(model.actionError)
                XCTAssertFalse(model.isPerformingAction)
                XCTAssertEqual(rig.api.requests(to: "/profile/42").count, refreshes + 1)
            }
        }
    }

    @MainActor
    func testListActionsRequireExplicitConfirmationBeforeRefreshingProfile() async throws {
        for adding in [true, false] {
            for json in ["{}", #"{"code":null}"#, #"{"code":2}"#] {
                let rig = ProfileTestRig()
                try await rig.signIn()
                let model = try model(rig)
                let destination: ProfileListStatus? = adding ? .completed : nil
                let path = adding ? "/profile/list/add/3/71" : "/profile/list/delete/1/71"
                let refreshes = rig.api.requests(to: "/profile/42").count
                rig.api.enqueue(path, json: json)
                await model.setList(destination)
                XCTAssertEqual(model.release?.profileListStatus, 1)
                XCTAssertEqual(model.release?.isFavorite, false)
                XCTAssertNotNil(model.actionError)
                XCTAssertFalse(model.isPerformingAction)
                XCTAssertEqual(rig.api.requests(to: path).count, 1)
                XCTAssertEqual(rig.api.requests(to: "/profile/42").count, refreshes)

                rig.api.enqueue(path, json: #"{"code":0}"#)
                rig.api.enqueue("/release/71", json: detailResponse(isFavorite: false, listStatus: destination?.rawValue))
                await model.setList(destination)
                XCTAssertEqual(model.release?.profileListStatus, destination?.rawValue)
                XCTAssertNil(model.actionError)
                XCTAssertFalse(model.isPerformingAction)
                XCTAssertEqual(rig.api.requests(to: "/profile/42").count, refreshes + 1)
            }
        }
    }

    @MainActor
    func testUnconfirmedVotesDoNotReloadReleaseOrRefreshProfile() async throws {
        for removing in [false, true] {
            for json in ["{}", #"{"code":null}"#, #"{"code":2}"#] {
                let rig = ProfileTestRig()
                try await rig.signIn()
                let model = try model(rig)
                let path = removing ? "/release/vote/delete/71" : "/release/vote/add/71/5"
                let refreshes = rig.api.requests(to: "/profile/42").count
                // A new score replaces an old one by deleting it first, as Android does.
                if !removing { rig.api.enqueue("/release/vote/delete/71", json: #"{"code":0}"#) }
                rig.api.enqueue(path, json: json)
                if removing { await model.removeVote() } else { await model.vote(.five) }
                XCTAssertEqual(model.release?.yourVote, removing ? 2 : nil)
                XCTAssertNotNil(model.actionError)
                XCTAssertFalse(model.isPerformingAction)
                XCTAssertEqual(rig.api.requests(to: path).count, 1)
                XCTAssertTrue(rig.api.requests(to: "/release/71").isEmpty)
                XCTAssertEqual(rig.api.requests(to: "/profile/42").count, refreshes)

                rig.api.enqueue(path, json: #"{"code":0}"#)
                rig.api.enqueue("/release/71", json: removing
                    ? #"{"code":0,"release":{"id":71,"your_vote":null}}"#
                    : #"{"code":0,"release":{"id":71,"your_vote":5}}"#)
                if removing { await model.removeVote() } else { await model.vote(.five) }
                XCTAssertEqual(model.release?.yourVote, removing ? nil : 5)
                XCTAssertNil(model.actionError)
                XCTAssertFalse(model.isPerformingAction)
                XCTAssertEqual(rig.api.requests(to: "/release/71").count, 1)
                XCTAssertEqual(rig.api.requests(to: "/profile/42").count, refreshes + 1)
            }
        }
    }

    @MainActor
    func testRemovingMissingOrUnknownListDoesNotGuessEndpointOrRefreshProfile() async throws {
        let statuses: [Int?] = [nil, 999]
        for status in statuses {
            let rig = ProfileTestRig()
            try await rig.signIn()
            let model = try model(rig, listStatus: status)
            let requests = rig.api.requests.count
            await model.setList(nil)
            XCTAssertEqual(model.release?.profileListStatus, status)
            XCTAssertFalse(model.isPerformingAction)
            XCTAssertNil(model.actionError)
            XCTAssertEqual(rig.api.requests.count, requests)
        }
    }

    @MainActor
    func testCancelledOptimisticActionsRollbackWithoutErrorOrProfileRefresh() async throws {
        for changesFavorite in [true, false] {
            let rig = ProfileTestRig()
            try await rig.signIn()
            let model = try model(rig)
            let path = changesFavorite ? "/favorite/add/71" : "/profile/list/add/3/71"
            let held = rig.api.hold(path)
            defer { held.respond("{}", status: 500) }
            let mutation = Task {
                if changesFavorite { await model.toggleFavorite() } else { await model.setList(.completed) }
            }
            defer { mutation.cancel() }
            await fulfillment(of: [held.arrived], timeout: 5)
            XCTAssertEqual(model.release?.isFavorite, changesFavorite)
            XCTAssertEqual(model.release?.profileListStatus, changesFavorite ? 1 : 3)
            mutation.cancel()
            await mutation.value
            await fulfillment(of: [held.cancelled], timeout: 5)
            XCTAssertEqual(model.release?.isFavorite, false)
            XCTAssertEqual(model.release?.profileListStatus, 1)
            XCTAssertNil(model.actionError)
            XCTAssertFalse(model.isPerformingAction)
            XCTAssertTrue(rig.api.requests(to: "/profile/42").isEmpty)
        }
    }

    @MainActor
    func testVoteExplicitlyReloadsDetailWhileActionRemainsSerialized() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = try model(rig)
        rig.api.enqueue("/release/vote/delete/71", json: #"{"code":0}"#)
        rig.api.enqueue("/release/vote/add/71/5", json: #"{"code":0}"#)
        let detail = rig.api.hold("/release/71")
        defer { detail.respond("{}", status: 500) }
        let vote = Task { await model.vote(.five) }
        defer { vote.cancel() }
        await fulfillment(of: [detail.arrived], timeout: 5)
        XCTAssertTrue(model.isPerformingAction)
        await model.toggleFavorite()
        XCTAssertTrue(rig.api.requests(to: "/favorite/add/71").isEmpty)
        detail.respond(#"{"code":0,"release":{"id":71,"your_vote":5,"grade":4.5}}"#)
        await vote.value
        XCTAssertEqual(model.release?.yourVote, 5)
        XCTAssertEqual(model.release?.grade, 4.5)
        XCTAssertFalse(model.isPerformingAction)
    }

    @MainActor
    func testLateActionErrorAfterNewLoginCannotRollbackOrShowError() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "first")
        let model = try model(rig)
        let held = rig.api.hold("/favorite/add/71")
        defer { held.respond("{}", status: 500) }
        let favorite = Task { await model.toggleFavorite() }
        defer { favorite.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        try await rig.signIn(token: "second")
        model.invalidate()
        held.respond(#"{"code":2}"#)
        await favorite.value
        XCTAssertFalse(model.hasCurrentViewer)
        XCTAssertNil(model.release)
        XCTAssertNil(model.actionError)
        XCTAssertFalse(model.isPerformingAction)
        let requests = rig.api.requests.count
        await model.load()
        await model.toggleFavorite()
        XCTAssertEqual(rig.api.requests.count, requests)
    }

    @MainActor
    func testGuestActionPromptsLoginWithoutSendingMutation() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let model = try model(rig)
        await model.toggleFavorite()
        XCTAssertTrue(rig.session.isPresentingAuth)
        XCTAssertEqual(model.release?.isFavorite, false)
        XCTAssertTrue(rig.api.requests.isEmpty)
    }

    @MainActor
    func testMismatchedPreloadedAndLoadedReleaseAreRejected() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let wrong = try profileTestDecode(Release.self, #"{"id":72}"#)
        let model = ReleaseDetailViewModel(releaseID: 71, preloaded: wrong, session: rig.session)
        XCTAssertNil(model.release)
        rig.api.enqueue("/release/71", json: #"{"code":0,"release":{"id":72}}"#)
        await model.load()
        XCTAssertNil(model.release)
        XCTAssertNotNil(model.errorMessage)
    }
}
