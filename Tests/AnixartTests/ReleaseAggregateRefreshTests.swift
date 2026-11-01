import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class ReleaseAggregateRefreshTests: XCTestCase {
    @MainActor
    private func model(_ rig: ProfileTestRig, favorite: Bool = false, status: Int? = 1) throws -> ReleaseDetailViewModel {
        let status = status.map { String($0) } ?? "null"
        let release = try profileTestDecode(Release.self,
            "{\"id\":71,\"is_favorite\":\(favorite),\"profile_list_status\":\(status),\"favorites_count\":10,\"watching_count\":8,\"plan_count\":3}")
        return ReleaseDetailViewModel(releaseID: 71, preloaded: release, session: rig.session)
    }

    @MainActor
    func testConfirmedFavouriteAndListReadsRefreshServerAggregatesAndOtherLiveFlags() async throws {
        for favoriteChange in [true, false] {
            let rig = ProfileTestRig()
            try await rig.signIn()
            let model = try model(rig)
            let path = favoriteChange ? "/favorite/add/71" : "/profile/list/add/3/71"
            rig.api.enqueue(path, json: #"{"code":0}"#)
            // A concurrent device/account update is included in this fresh read.
            // Do not merge unrelated fields back from the old preload.
            rig.api.enqueue("/release/71", json: favoriteChange
                ? #"{"code":0,"release":{"id":71,"is_favorite":true,"profile_list_status":4,"favorites_count":91,"watching_count":28,"plan_count":13}}"#
                : #"{"code":0,"release":{"id":71,"is_favorite":true,"profile_list_status":3,"favorites_count":92,"watching_count":29,"plan_count":14}}"#)
            if favoriteChange { await model.toggleFavorite() } else { await model.setList(.completed) }
            XCTAssertEqual(model.release?.favoriteCount, favoriteChange ? 91 : 92)
            XCTAssertEqual(model.release?.watchingCount, favoriteChange ? 28 : 29)
            XCTAssertEqual(model.release?.planCount, favoriteChange ? 13 : 14)
            XCTAssertEqual(model.release?.isFavorite, true)
            XCTAssertEqual(model.release?.profileListStatus, favoriteChange ? 4 : 3)
            XCTAssertNil(model.errorMessage)
            XCTAssertNil(model.actionError)
            XCTAssertEqual(rig.api.requests(to: "/release/71").count, 1)
            XCTAssertEqual(rig.api.requests(to: "/profile/42").count, 1)
        }
    }

    @MainActor
    func testFailedAggregateReadNeverRollsBackAcknowledgedAddOrRemove() async throws {
        for operation in 0...3 {
            for failure in [#"{"code":2}"#, #"{"code":0}"#, #"{"code":0,"release":{"id":999}}"#] {
                let rig = ProfileTestRig()
                try await rig.signIn()
                let model = try model(rig, favorite: operation == 1, status: operation == 3 ? 4 : 1)
                let paths = ["/favorite/add/71", "/favorite/delete/71", "/profile/list/add/3/71", "/profile/list/delete/4/71"]
                rig.api.enqueue(paths[operation], json: #"{"code":0}"#)
                rig.api.enqueue("/release/71", json: failure)
                if operation < 2 { await model.toggleFavorite() }
                else { await model.setList(operation == 2 ? .completed : nil) }
                XCTAssertEqual(model.release?.isFavorite, operation == 0)
                XCTAssertEqual(model.release?.profileListStatus, operation == 3 ? nil : (operation == 2 ? 3 : 1))
                XCTAssertEqual(model.release?.favoriteCount, 10, "Never guess aggregate +/-1")
                XCTAssertEqual(model.release?.watchingCount, 8)
                XCTAssertNotNil(model.errorMessage)
                XCTAssertNil(model.actionError)
                XCTAssertFalse(model.isLoading)
                XCTAssertFalse(model.isPerformingAction)
                XCTAssertEqual(rig.api.requests(to: paths[operation]).count, 1)
            }
        }
    }

    @MainActor
    func testCancellationDuringAggregateKeepsAcknowledgementWithoutFalseWriteError() async throws {
        for favoriteChange in [true, false] {
            let rig = ProfileTestRig()
            try await rig.signIn()
            let model = try model(rig)
            rig.api.enqueue(favoriteChange ? "/favorite/add/71" : "/profile/list/add/3/71", json: #"{"code":0}"#)
            let held = rig.api.hold("/release/71")
            defer { held.respond("{}", status: 500) }
            let action = Task {
                if favoriteChange { await model.toggleFavorite() } else { await model.setList(.completed) }
            }
            defer { action.cancel() }
            await fulfillment(of: [held.arrived], timeout: 5)
            XCTAssertTrue(model.isPerformingAction)
            action.cancel()
            await action.value
            XCTAssertEqual(model.release?.isFavorite, favoriteChange)
            XCTAssertEqual(model.release?.profileListStatus, favoriteChange ? 1 : 3)
            XCTAssertEqual(model.release?.favoriteCount, 10)
            XCTAssertNil(model.errorMessage)
            XCTAssertNil(model.actionError)
            XCTAssertFalse(model.isLoading)
            XCTAssertFalse(model.isPerformingAction)
            XCTAssertTrue(rig.api.requests(to: "/profile/42").isEmpty)
        }
    }

    @MainActor
    func testSupersededAggregateCannotAdoptOldFlagsOrRefreshLaterLogin() async throws {
        for favoriteChange in [true, false] {
            let rig = ProfileTestRig()
            try await rig.signIn(token: "first")
            let model = try model(rig)
            rig.api.enqueue(favoriteChange ? "/favorite/add/71" : "/profile/list/add/3/71", json: #"{"code":0}"#)
            let held = rig.api.hold("/release/71")
            defer { held.respond("{}", status: 500) }
            let action = Task {
                if favoriteChange { await model.toggleFavorite() } else { await model.setList(.completed) }
            }
            defer { action.cancel() }
            await fulfillment(of: [held.arrived], timeout: 5)
            try await rig.signIn(token: "second")
            model.invalidate()
            held.respond(#"{"code":0,"release":{"id":71,"is_favorite":false,"profile_list_status":1,"favorites_count":999}}"#)
            await action.value
            XCTAssertNil(model.release)
            XCTAssertNil(model.errorMessage)
            XCTAssertNil(model.actionError)
            XCTAssertFalse(model.isPerformingAction)
            XCTAssertFalse(model.hasCurrentViewer)
            XCTAssertTrue(rig.api.requests(to: "/profile/42").isEmpty)
            let query = try XCTUnwrap(held.request?.url).query
            XCTAssertTrue(query?.contains("token=first") == true)
            XCTAssertFalse(query?.contains("token=second") == true)
        }
    }

    @MainActor
    func testPreActionLoadCannotStopOrOverwriteNewAggregateRefresh() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = try model(rig)
        let old = rig.api.hold("/release/71")
        defer { old.respond("{}", status: 500) }
        let loading = Task { await model.load() }
        defer { loading.cancel() }
        await fulfillment(of: [old.arrived], timeout: 5)
        rig.api.enqueue("/favorite/add/71", json: #"{"code":0}"#)
        let fresh = rig.api.hold("/release/71")
        defer { fresh.respond("{}", status: 500) }
        let action = Task { await model.toggleFavorite() }
        defer { action.cancel() }
        await fulfillment(of: [fresh.arrived], timeout: 5)
        old.respond(#"{"code":0,"release":{"id":71,"is_favorite":false,"favorites_count":1}}"#)
        await loading.value
        XCTAssertEqual(model.release?.isFavorite, true)
        XCTAssertTrue(model.isLoading)
        XCTAssertTrue(model.isPerformingAction)
        await model.setList(.completed)
        XCTAssertTrue(rig.api.requests(to: "/profile/list/add/3/71").isEmpty)
        fresh.respond(#"{"code":0,"release":{"id":71,"is_favorite":true,"favorites_count":55}}"#)
        await action.value
        XCTAssertEqual(model.release?.favoriteCount, 55)
        XCTAssertEqual(model.release?.isFavorite, true)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testSameDetailStatusSelectionDoesNotWriteOrInvalidateExistingRead() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = try model(rig)
        let held = rig.api.hold("/release/71")
        defer { held.respond("{}", status: 500) }
        let loading = Task { await model.load() }
        defer { loading.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        let requests = rig.api.requests.count
        await model.setList(.watching)
        XCTAssertEqual(rig.api.requests.count, requests)
        XCTAssertTrue(model.isLoading)
        held.respond(#"{"code":0,"release":{"id":71,"profile_list_status":1,"favorites_count":77}}"#)
        await loading.value
        XCTAssertEqual(model.release?.favoriteCount, 77)
        XCTAssertFalse(model.isPerformingAction)
    }
}
