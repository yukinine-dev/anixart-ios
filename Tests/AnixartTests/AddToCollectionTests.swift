import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class AddToCollectionTests: XCTestCase {
    private func collection(id: Int = 9, creatorID: Int = 42) throws -> ReleaseCollection {
        try profileTestDecode(ReleaseCollection.self, "{\"id\":\(id),\"creator\":{\"id\":\(creatorID)}}")
    }

    @MainActor
    func testAdditionReportsSuccessOnlyAfterConfirmedCodeZero() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = AddToCollectionViewModel(releaseID: 71, viewer: rig.session.viewerKey, session: rig.session)
        let held = rig.api.hold("/collectionMy/release/add/9")
        defer { held.respond("{}", status: 500) }
        let target = try collection()
        let addition = Task { await model.add(to: target) }
        defer { addition.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        XCTAssertTrue(model.isAdding)
        XCTAssertEqual(model.addingCollectionID, 9)
        XCTAssertEqual(held.request?.httpMethod, "GET")
        XCTAssertTrue(held.request?.url?.query?.contains("release_id=71") == true)
        held.respond(#"{"code":0}"#)
        let added = await addition.value
        XCTAssertTrue(added)
        XCTAssertFalse(model.isAdding)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(rig.api.requests(to: "/profile/42").count, 1)
    }

    @MainActor
    func testEmptyResponseDoesNotClosePickerOrRefreshProfile() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = AddToCollectionViewModel(releaseID: 71, viewer: rig.session.viewerKey, session: rig.session)
        rig.api.enqueue("/collectionMy/release/add/9", json: "{}")
        let added = try await model.add(to: collection())
        XCTAssertFalse(added)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(rig.api.requests(to: "/profile/42").isEmpty)
    }

    @MainActor
    func testEveryKnownBusinessErrorStaysVisibleWithoutReportingSuccess() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = AddToCollectionViewModel(releaseID: 71, viewer: rig.session.viewerKey, session: rig.session)
        let expected = [
            2: "Коллекция не найдена. Обновите список.",
            3: "Можно добавлять релизы только в свои коллекции.",
            4: "Этот релиз недоступен для добавления.",
            5: "Релиз уже есть в этой коллекции.",
            6: "Коллекция удалена. Обновите список.",
            7: "В коллекции достигнут лимит релизов."
        ]
        for code in 2...7 {
            rig.api.enqueue("/collectionMy/release/add/9", json: "{\"code\":\(code)}")
            let added = try await model.add(to: collection())
            XCTAssertFalse(added)
            XCTAssertEqual(model.errorMessage, expected[code])
            XCTAssertFalse(model.isAdding)
        }
        XCTAssertTrue(rig.api.requests(to: "/profile/42").isEmpty)
    }

    @MainActor
    func testForeignCollectionCannotSendAMutation() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = AddToCollectionViewModel(releaseID: 71, viewer: rig.session.viewerKey, session: rig.session)
        let added = try await model.add(to: collection(creatorID: 43))
        XCTAssertFalse(added)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(rig.api.requests(to: "/collectionMy/release/add/9").isEmpty)
    }

    @MainActor
    func testOwnCollectionPickerPaginatesAndDeduplicates() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        rig.api.enqueue("/collection/all/profile/42/0", json: #"{"code":0,"content":[{"id":9},{"id":10}],"current_page":0,"total_page_count":2,"total_count":3}"#)
        rig.api.enqueue("/collection/all/profile/42/1", json: #"{"code":0,"content":[{"id":10},{"id":11}],"current_page":1,"total_page_count":2,"total_count":3}"#)
        let model = AddToCollectionViewModel(releaseID: 71, viewer: rig.session.viewerKey, session: rig.session)
        let paginator = try XCTUnwrap(model.paginator)
        await paginator.loadFirstPageIfNeeded()
        await paginator.loadNextPage()
        XCTAssertEqual(paginator.items.map(\.id), [9, 10, 11])
        XCTAssertFalse(paginator.hasMore)
        XCTAssertTrue(rig.api.requests(to: "/collection/all/profile/42/1").first?.url?.query?.contains("token=test-token") == true)
    }

    @MainActor
    func testConcurrentSelectionCannotAddToAnotherCollectionDuringMutation() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = AddToCollectionViewModel(releaseID: 71, viewer: rig.session.viewerKey, session: rig.session)
        let held = rig.api.hold("/collectionMy/release/add/9")
        defer { held.respond("{}", status: 500) }
        let target = try collection()
        let first = Task { await model.add(to: target) }
        defer { first.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        let second = try await model.add(to: collection(id: 10))
        XCTAssertFalse(second)
        XCTAssertTrue(rig.api.requests(to: "/collectionMy/release/add/10").isEmpty)
        held.respond(#"{"code":0}"#)
        let added = await first.value
        XCTAssertTrue(added)
    }

    @MainActor
    func testLateAdditionCannotReportSuccessForNewLoginToSameProfile() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "first")
        let model = AddToCollectionViewModel(releaseID: 71, viewer: rig.session.viewerKey, session: rig.session)
        let held = rig.api.hold("/collectionMy/release/add/9")
        defer { held.respond("{}", status: 500) }
        let target = try collection()
        let addition = Task { await model.add(to: target) }
        defer { addition.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        try await rig.signIn(token: "second")
        model.invalidate()
        held.respond(#"{"code":0}"#)
        let added = await addition.value
        XCTAssertFalse(added)
        XCTAssertFalse(model.hasCurrentViewer)
        XCTAssertNil(model.paginator)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(rig.api.requests(to: "/profile/42").isEmpty)
    }

    @MainActor
    func testGuestPickerPromptsSignInWithoutSendingAnAddition() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let model = AddToCollectionViewModel(releaseID: 71, viewer: rig.session.viewerKey, session: rig.session)
        let added = try await model.add(to: collection())
        XCTAssertFalse(added)
        XCTAssertTrue(rig.session.isPresentingAuth)
        XCTAssertNil(model.paginator)
        XCTAssertTrue(rig.api.requests.isEmpty)
    }
}
