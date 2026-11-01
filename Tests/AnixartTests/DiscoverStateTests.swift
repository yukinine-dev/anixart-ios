import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class DiscoverStateTests: XCTestCase {
    private func page(_ ids: [Int]) -> String {
        "{\"code\":0,\"content\":[" + ids.map { "{\"id\":\($0)}" }.joined(separator: ",") + "]}"
    }

    private func enqueuePublic(_ rig: ProfileTestRig, ids: [Int]) {
        rig.api.enqueue("/discover/interesting", json: page(ids))
        rig.api.enqueue("/discover/discussing", json: page(ids))
        rig.api.enqueue("/discover/comments", json: page(ids))
    }

    private func token(_ request: URLRequest) -> String? {
        request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == "token" }?.value
    }

    @MainActor
    func testGuestDiscoverNeverFetchesPersonalBlocksAndDeduplicatesVisibleContent() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        rig.api.enqueue("/discover/interesting", json: #"{"code":0,"content":[{"id":1},{"id":1},{"id":2,"isHidden":true}]}"#)
        rig.api.enqueue("/discover/discussing", json: page([3, 3]))
        rig.api.enqueue("/discover/comments", json: page([4, 4]))
        let model = DiscoverViewModel(session: rig.session)
        await model.loadIfNeeded()
        XCTAssertEqual(model.banners.map(\.id), [1])
        XCTAssertEqual(model.discussing.map(\.id), [3])
        XCTAssertEqual(model.commentsOfTheWeek.map(\.id), [4])
        XCTAssertTrue(model.continueWatching.isEmpty)
        XCTAssertTrue(model.recommendations.isEmpty)
        XCTAssertTrue(rig.api.requests(to: "/discover/watching/0").isEmpty)
        XCTAssertTrue(rig.api.requests(to: "/discover/recommendations/0").isEmpty)
        XCTAssertTrue(rig.api.requests.allSatisfy { token($0) == nil })
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.showsRecommendationExplanation)
    }

    @MainActor
    func testSignedDiscoverScopesPersonalBlocksButPublicBannersAndCommentsStayTokenFree() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "owner")
        enqueuePublic(rig, ids: [1])
        rig.api.enqueue("/discover/watching/0", json: page([2]))
        rig.api.enqueue("/discover/recommendations/0", json: page([3]))
        let model = DiscoverViewModel(session: rig.session)
        await model.load()
        XCTAssertEqual(model.continueWatching.map(\.id), [2])
        XCTAssertEqual(model.recommendations.map(\.id), [3])
        XCTAssertEqual(token(try XCTUnwrap(rig.api.requests(to: "/discover/watching/0").first)), "owner")
        XCTAssertEqual(token(try XCTUnwrap(rig.api.requests(to: "/discover/recommendations/0").first)), "owner")
        XCTAssertEqual(token(try XCTUnwrap(rig.api.requests(to: "/discover/discussing").first)), "owner")
        XCTAssertNil(token(try XCTUnwrap(rig.api.requests(to: "/discover/interesting").first)))
        XCTAssertNil(token(try XCTUnwrap(rig.api.requests(to: "/discover/comments").first)))
    }

    @MainActor
    func testPartialRefreshFailureKeepsPreviousBlockButSuccessfulEmptyActuallyClearsIt() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        enqueuePublic(rig, ids: [1])
        let model = DiscoverViewModel(session: rig.session)
        await model.load()
        rig.api.enqueue("/discover/interesting", json: #"{"code":2}"#)
        rig.api.enqueue("/discover/discussing", json: page([2]))
        rig.api.enqueue("/discover/comments", json: page([]))
        await model.load()
        XCTAssertEqual(model.banners.map(\.id), [1])
        XCTAssertEqual(model.discussing.map(\.id), [2])
        XCTAssertTrue(model.commentsOfTheWeek.isEmpty)
        XCTAssertEqual(model.failedBlocks, ["Интересное"])
        XCTAssertNotNil(model.partialErrorMessage)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testOlderConcurrentDiscoverLoadCannotOverwriteNewSnapshot() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let paths = ["/discover/interesting", "/discover/discussing", "/discover/comments"]
        let held = paths.map { rig.api.hold($0) }
        defer { held.forEach { $0.respond("{}", status: 500) } }
        let model = DiscoverViewModel(session: rig.session)
        let old = Task { await model.load() }
        defer { old.cancel() }
        await fulfillment(of: held.map(\.arrived), timeout: 5)
        enqueuePublic(rig, ids: [2])
        await model.load()
        held.forEach { $0.respond(page([1])) }
        await old.value
        XCTAssertEqual(model.banners.map(\.id), [2])
        XCTAssertEqual(model.discussing.map(\.id), [2])
        XCTAssertEqual(model.commentsOfTheWeek.map(\.id), [2])
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.failedBlocks.isEmpty)
    }

    @MainActor
    func testCancelledDiscoverLoadCommitsNothingAndCanBeRetriedOnAppearance() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let held = ["/discover/interesting", "/discover/discussing", "/discover/comments"].map { rig.api.hold($0) }
        defer { held.forEach { $0.respond("{}", status: 500) } }
        let model = DiscoverViewModel(session: rig.session)
        let load = Task { await model.load() }
        defer { load.cancel() }
        await fulfillment(of: held.map(\.arrived), timeout: 5)
        load.cancel()
        await load.value
        XCTAssertTrue(model.isEmpty)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.failedBlocks.isEmpty)
        enqueuePublic(rig, ids: [2])
        await model.loadIfNeeded()
        XCTAssertEqual(model.discussing.map(\.id), [2])
    }

    @MainActor
    func testSessionChangeRejectsLateDiscoverAndNewModelLoadsCurrentPersonalData() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let held = ["/discover/interesting", "/discover/discussing", "/discover/comments"].map { rig.api.hold($0) }
        defer { held.forEach { $0.respond("{}", status: 500) } }
        let previous = DiscoverViewModel(session: rig.session)
        let load = Task { await previous.load() }
        defer { load.cancel() }
        await fulfillment(of: held.map(\.arrived), timeout: 5)
        try await rig.signIn(token: "owner")
        held.forEach { $0.respond(page([1])) }
        await load.value
        XCTAssertTrue(previous.isEmpty)
        XCTAssertFalse(previous.hasCurrentViewer)
        XCTAssertNil(previous.errorMessage)
        enqueuePublic(rig, ids: [2])
        rig.api.enqueue("/discover/watching/0", json: page([3]))
        rig.api.enqueue("/discover/recommendations/0", json: page([4]))
        let current = DiscoverViewModel(session: rig.session)
        await current.loadIfNeeded()
        XCTAssertEqual(current.discussing.map(\.id), [2])
        XCTAssertEqual(current.continueWatching.map(\.id), [3])
        XCTAssertEqual(current.recommendations.map(\.id), [4])
    }

    @MainActor
    func testValidEmptyDiscoverIsNotNetworkFailureAndDoesNotReloadRepeatedly() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        enqueuePublic(rig, ids: [])
        let model = DiscoverViewModel(session: rig.session)
        await model.loadIfNeeded()
        XCTAssertTrue(model.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.partialErrorMessage)
        await model.loadIfNeeded()
        XCTAssertEqual(rig.api.requests(to: "/discover/interesting").count, 1)
    }

    @MainActor
    func testRecommendationExplanationDistinguishesEmptyPersonalFeedFromFailure() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        enqueuePublic(rig, ids: [1])
        rig.api.enqueue("/discover/watching/0", json: page([]))
        rig.api.enqueue("/discover/recommendations/0", json: page([]))
        let model = DiscoverViewModel(session: rig.session)
        await model.load()
        XCTAssertTrue(model.showsRecommendationExplanation)
        enqueuePublic(rig, ids: [1])
        rig.api.enqueue("/discover/watching/0", json: page([]))
        rig.api.enqueue("/discover/recommendations/0", json: #"{"code":2}"#)
        await model.load()
        XCTAssertFalse(model.showsRecommendationExplanation)
        XCTAssertTrue(model.failedBlocks.contains("Рекомендации"))
    }
}
