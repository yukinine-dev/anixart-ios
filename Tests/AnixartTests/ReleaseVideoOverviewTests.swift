import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class ReleaseVideoOverviewTests: XCTestCase {
    private func overview(_ ids: [Int], releaseID: Int = 71, blocks: String = "[]") -> String {
        let rows = ids.map { "{\"id\":\($0),\"title\":\"Видео\",\"player_url\":\"https://video-tests.invalid/player/\($0)\"}" }.joined(separator: ",")
        return "{\"code\":0,\"release\":{\"id\":\(releaseID),\"title_ru\":\"Тайтл\"},\"last_videos\":[\(rows)],\"blocks\":\(blocks),\"streaming_platforms\":[{\"id\":3,\"name\":\"Сервис\",\"url\":\"https://streaming-tests.invalid/release\"}],\"can_appeal\":false}"
    }
    private func page(_ ids: [Int]) -> String {
        let rows = ids.map { "{\"id\":\($0)}" }.joined(separator: ",")
        return "{\"code\":0,\"content\":[\(rows)],\"current_page\":0,\"total_page_count\":0,\"total_count\":0}"
    }

    @MainActor
    func testHubLoadsRealBlocksStreamingAndRecentVideosFromDistinctPublicEndpoint() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let blocks = #"[{"category":{"id":9,"name":"Опенинги"},"videos":[{"id":201}]}]"#
        rig.api.enqueue("/video/release/71", json: overview([1, 2], blocks: blocks))
        let model = ReleaseVideoOverviewModel(releaseID: 71, viewer: rig.session.viewerKey, session: rig.session)
        await model.loadIfNeeded()
        XCTAssertEqual(model.release?.displayTitle, "Тайтл")
        XCTAssertEqual(model.sections.first?.category?.name, "Опенинги")
        XCTAssertEqual(model.sections.first?.categoryID, 9)
        XCTAssertEqual(model.sections.first?.videos.map(\.id), [201])
        XCTAssertEqual(model.videos.map(\.id), [1, 2])
        XCTAssertEqual(model.streamingPlatforms.first?.destinationURL?.host, "streaming-tests.invalid")
        XCTAssertFalse(model.hasMore)
        let request = try XCTUnwrap(rig.api.requests(to: "/video/release/71").first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "API-Version"), "2")
        XCTAssertTrue(rig.api.requests(to: "/video/release/71/0").isEmpty)
        XCTAssertTrue(rig.api.requests(to: "/video/release/categories").isEmpty)
    }

    @MainActor
    func testRecentPageContinuationUsesRaw25AndRequestedPageAfterSeed() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        rig.api.enqueue("/video/release/71", json: overview(Array(1...24) + [24]))
        rig.api.enqueue("/video/release/71/1", json: page(Array(24...48)))
        rig.api.enqueue("/video/release/71/2", json: page([48, 49]))
        let model = ReleaseVideoOverviewModel(releaseID: 71, viewer: rig.session.viewerKey, session: rig.session)
        await model.loadIfNeeded()
        XCTAssertEqual(model.videos.count, 24)
        XCTAssertTrue(model.hasMore)
        await model.loadNextPage()
        XCTAssertTrue(model.hasMore)
        await model.loadNextPage()
        XCTAssertEqual(model.videos.map(\.id), Array(1...49))
        XCTAssertFalse(model.hasMore)
        await model.loadNextPage()
        XCTAssertEqual(rig.api.requests(to: "/video/release/71/1").count, 1)
        XCTAssertEqual(rig.api.requests(to: "/video/release/71/2").count, 1)
    }

    @MainActor
    func testNextPageFailureRetriesSamePageAndKeepsHubContent() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        rig.api.enqueue("/video/release/71", json: overview(Array(1...25)))
        rig.api.enqueue("/video/release/71/1", json: #"{"code":2}"#)
        rig.api.enqueue("/video/release/71/1", json: page([26]))
        let model = ReleaseVideoOverviewModel(releaseID: 71, viewer: rig.session.viewerKey, session: rig.session)
        await model.loadIfNeeded()
        await model.loadNextPage()
        XCTAssertEqual(model.failedPage, 1)
        XCTAssertEqual(model.videos.count, 25)
        XCTAssertEqual(model.streamingPlatforms.count, 1)
        await model.retry()
        XCTAssertEqual(model.videos.map(\.id), Array(1...26))
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(rig.api.requests(to: "/video/release/71").count, 1)
        XCTAssertEqual(rig.api.requests(to: "/video/release/71/1").count, 2)
    }

    @MainActor
    func testRefreshFailureKeepsSnapshotAndDoesNotPretendThereAreNoVideos() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        rig.api.enqueue("/video/release/71", json: overview([1, 2]))
        let model = ReleaseVideoOverviewModel(releaseID: 71, viewer: rig.session.viewerKey, session: rig.session)
        await model.loadIfNeeded()
        rig.api.enqueue("/video/release/71", json: #"{"code":2}"#)
        await model.reload()
        XCTAssertEqual(model.videos.map(\.id), [1, 2])
        XCTAssertEqual(model.release?.id, 71)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.failedPage, 0)
        rig.api.enqueue("/video/release/71", json: overview([3]))
        await model.retry()
        XCTAssertEqual(model.videos.map(\.id), [3])
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testMissingOrWrongReleaseHubIsAVisibleFailureNotEmptySuccess() async {
        for json in [#"{"code":0}"#, #"{"code":0,"release":{"id":71}}"#, overview([], releaseID: 999)] {
            let rig = ProfileTestRig()
            await rig.session.restore()
            rig.api.enqueue("/video/release/71", json: json)
            let model = ReleaseVideoOverviewModel(releaseID: 71, viewer: rig.session.viewerKey, session: rig.session)
            await model.loadIfNeeded()
            XCTAssertNotNil(model.errorMessage)
            XCTAssertEqual(model.failedPage, 0)
            XCTAssertNil(model.release)
            XCTAssertTrue(model.videos.isEmpty)
            XCTAssertFalse(model.hasMore)
        }
    }

    @MainActor
    func testRefreshRejectsAnOlderContinuationPage() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        rig.api.enqueue("/video/release/71", json: overview(Array(1...25)))
        let model = ReleaseVideoOverviewModel(releaseID: 71, viewer: rig.session.viewerKey, session: rig.session)
        await model.loadIfNeeded()
        let held = rig.api.hold("/video/release/71/1")
        defer { held.respond("{}", status: 500) }
        let old = Task { await model.loadNextPage() }
        defer { old.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        rig.api.enqueue("/video/release/71", json: overview([50]))
        await model.reload()
        held.respond(page([26]))
        await old.value
        XCTAssertEqual(model.videos.map(\.id), [50])
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.hasMore)
    }

    @MainActor
    func testCancelledInitialHubLoadCanRetryWithoutFalseFailure() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let held = rig.api.hold("/video/release/71")
        defer { held.respond("{}", status: 500) }
        let model = ReleaseVideoOverviewModel(releaseID: 71, viewer: rig.session.viewerKey, session: rig.session)
        let loading = Task { await model.loadIfNeeded() }
        defer { loading.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        loading.cancel()
        await loading.value
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.errorMessage)
        rig.api.enqueue("/video/release/71", json: overview([5]))
        await model.loadIfNeeded()
        XCTAssertEqual(model.videos.map(\.id), [5])
    }

    @MainActor
    func testOldViewerCannotAdoptLateHubOrReadWithALaterSession() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "first")
        let held = rig.api.hold("/video/release/71")
        defer { held.respond("{}", status: 500) }
        let model = ReleaseVideoOverviewModel(releaseID: 71, viewer: rig.session.viewerKey, session: rig.session)
        let loading = Task { await model.loadIfNeeded() }
        defer { loading.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        try await rig.signIn(token: "second")
        held.respond(overview([1]))
        await loading.value
        XCTAssertNil(model.release)
        XCTAssertTrue(model.videos.isEmpty)
        XCTAssertNil(model.errorMessage)
        let count = rig.api.requests.count
        await model.reload()
        await model.retry()
        await model.loadNextPage()
        XCTAssertEqual(rig.api.requests.count, count)
        XCTAssertFalse(model.hasCurrentViewer)
    }

    @MainActor
    func testCategoryShowAllUsesRaw25AndValidServerCategoryNotItsName() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let raw = (Array(1...24) + [24]).map { "{\"id\":\($0)}" }.joined(separator: ",")
        let blocks = "[{\"category\":{\"id\":9,\"name\":\"999\"},\"videos\":[\(raw)]},{\"category\":{\"id\":0},\"videos\":[\(raw)]},{\"videos\":[\(raw)]}]"
        rig.api.enqueue("/video/release/71", json: overview([], blocks: blocks))
        let model = ReleaseVideoOverviewModel(releaseID: 71, viewer: rig.session.viewerKey, session: rig.session)
        await model.loadIfNeeded()
        XCTAssertEqual(model.sections.first?.videos.count, 24)
        XCTAssertEqual(model.sections.first?.rawCount, 25)
        XCTAssertEqual(model.sections.first?.categoryID, 9)
        XCTAssertEqual(model.sections.map(\.showsAll), [true, false, false])
    }

    @MainActor
    func testDisappearCancelsCommitButAllowsNewFirstLoadAndInvalidationIsPermanent() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let held = rig.api.hold("/video/release/71")
        defer { held.respond("{}", status: 500) }
        let model = ReleaseVideoOverviewModel(releaseID: 71, viewer: rig.session.viewerKey, session: rig.session)
        let old = Task { await model.loadIfNeeded() }
        defer { old.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        model.cancelLoads()
        rig.api.enqueue("/video/release/71", json: overview([2]))
        await model.loadIfNeeded()
        held.respond(overview([1]))
        await old.value
        XCTAssertEqual(model.videos.map(\.id), [2])
        model.invalidate()
        let count = rig.api.requests.count
        await model.reload()
        XCTAssertNil(model.release)
        XCTAssertTrue(model.videos.isEmpty)
        XCTAssertEqual(rig.api.requests.count, count)
    }
}
