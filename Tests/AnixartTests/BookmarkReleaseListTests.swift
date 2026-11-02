import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class BookmarkReleaseListTests: XCTestCase {
    private func page(_ ids: [Int]) -> String {
        let rows = ids.map { "{\"id\":\($0)}" }.joined(separator: ",")
        return "{\"code\":0,\"content\":[\(rows)],\"current_page\":0,\"total_page_count\":0,\"total_count\":\(ids.count)}"
    }

    private func query(_ name: String, in request: URLRequest) -> String? {
        request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == name }?.value
    }

    @MainActor
    func testAllBookmarkListsUseTheirOwnEndpointSortAndViewerToken() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "owner")
        let examples: [(BookmarkReleaseList.Kind, String)] = [
            (.favorites, "/favorite/all/0"), (.history, "/history/0"), (.list(.completed), "/profile/list/all/3/0")
        ]
        for (kind, path) in examples {
            let model = BookmarkReleaseListModel(kind: kind, sort: .addedAscending, session: rig.session)
            rig.api.enqueue(path, json: page([71]))
            await model.paginator.loadFirstPageIfNeeded()
            XCTAssertEqual(model.paginator.items.map(\.id), [71])
            let request = try XCTUnwrap(rig.api.requests(to: path).last)
            XCTAssertEqual(query("token", in: request), "owner")
            XCTAssertEqual(query("sort", in: request), kind == .history ? nil : "2")
        }
    }

    @MainActor
    func testBookmarksPageByRawCountEvenWithZeroMetadataAndRepeatedRows() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = BookmarkReleaseListModel(kind: .favorites, sort: .addedDescending, session: rig.session)
        rig.api.enqueue("/favorite/all/0", json: page(Array(1...24) + [24]))
        rig.api.enqueue("/favorite/all/1", json: page([24, 25]))
        await model.paginator.loadFirstPageIfNeeded()
        XCTAssertEqual(model.paginator.items.count, 24)
        XCTAssertTrue(model.paginator.hasMore)
        await model.paginator.loadNextPage()
        XCTAssertEqual(model.paginator.items.map(\.id), Array(1...25))
        XCTAssertFalse(model.paginator.hasMore)
        await model.paginator.loadNextPage()
        XCTAssertEqual(rig.api.requests(to: "/favorite/all/1").count, 1)
    }

    @MainActor
    func testAnOldBookmarksScreenCannotReadOrDeleteWithALaterAccount() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "first")
        let model = BookmarkReleaseListModel(kind: .history, sort: .addedDescending, session: rig.session)
        rig.api.enqueue("/history/0", json: page(Array(1...25)))
        await model.paginator.loadFirstPageIfNeeded()
        try await rig.signIn(token: "second")
        let requests = rig.api.requests.count
        await model.reload()
        await model.paginator.loadNextPage()
        await model.removeFromHistory(releaseID: 1)
        XCTAssertFalse(model.hasCurrentViewer)
        XCTAssertEqual(rig.api.requests.count, requests)
        XCTAssertEqual(model.paginator.items.map(\.id), Array(1...25))
        XCTAssertNil(model.actionError)
    }

    @MainActor
    func testHistoryDeleteNeedsAcknowledgementAndFailureKeepsTheEntry() async throws {
        for unconfirmed in ["{}", #"{"code":null}"#, #"{"code":2}"#] {
            let rig = ProfileTestRig()
            try await rig.signIn()
            let model = BookmarkReleaseListModel(kind: .history, sort: .addedDescending, session: rig.session)
            rig.api.enqueue("/history/0", json: page([71, 72]))
            await model.paginator.loadFirstPageIfNeeded()
            rig.api.enqueue("/history/delete/71", json: unconfirmed)
            await model.removeFromHistory(releaseID: 71)
            XCTAssertEqual(model.paginator.items.map(\.id), [71, 72])
            XCTAssertNotNil(model.actionError)
            XCTAssertTrue(model.removingIDs.isEmpty)
            XCTAssertEqual(rig.api.requests(to: "/history/0").count, 1)
            rig.api.enqueue("/history/delete/71", json: #"{"code":0}"#)
            rig.api.enqueue("/history/0", json: page([72]))
            await model.removeFromHistory(releaseID: 71)
            XCTAssertEqual(model.paginator.items.map(\.id), [72])
            XCTAssertNil(model.actionError)
        }
    }

    @MainActor
    func testHistoryDeleteRebasesAndAnOlderNextPageCannotReinsertTheEntry() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = BookmarkReleaseListModel(kind: .history, sort: .addedDescending, session: rig.session)
        rig.api.enqueue("/history/0", json: page(Array(1...25)))
        await model.paginator.loadFirstPageIfNeeded()
        let held = rig.api.hold("/history/1")
        defer { held.respond("{}", status: 500) }
        let next = Task { await model.paginator.loadNextPage() }
        defer { next.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        rig.api.enqueue("/history/delete/1", json: #"{"code":0}"#)
        rig.api.enqueue("/history/0", json: page(Array(2...25)))
        await model.removeFromHistory(releaseID: 1)
        held.respond(page([1, 26]))
        await next.value
        XCTAssertEqual(model.paginator.items.map(\.id), Array(2...25))
        XCTAssertFalse(model.paginator.hasMore)
    }

    @MainActor
    func testLateHistoryDeleteAcknowledgementDoesNotAffectTheNewViewer() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "first")
        let model = BookmarkReleaseListModel(kind: .history, sort: .addedDescending, session: rig.session)
        rig.api.enqueue("/history/0", json: page([71]))
        await model.paginator.loadFirstPageIfNeeded()
        let held = rig.api.hold("/history/delete/71")
        defer { held.respond("{}", status: 500) }
        let removal = Task { await model.removeFromHistory(releaseID: 71) }
        defer { removal.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        try await rig.signIn(token: "second")
        let requests = rig.api.requests.count
        held.respond(#"{"code":0}"#)
        await removal.value
        XCTAssertEqual(query("token", in: try XCTUnwrap(held.request)), "first")
        XCTAssertEqual(model.paginator.items.map(\.id), [71])
        XCTAssertEqual(rig.api.requests.count, requests)
        XCTAssertNil(model.actionError)
        XCTAssertTrue(model.removingIDs.isEmpty)
    }

    @MainActor
    func testFavoritesAndUnknownHistoryEntriesNeverDispatchHistoryDeletes() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let favorites = BookmarkReleaseListModel(kind: .favorites, sort: .addedDescending, session: rig.session)
        rig.api.enqueue("/favorite/all/0", json: page([71]))
        await favorites.paginator.loadFirstPageIfNeeded()
        let history = BookmarkReleaseListModel(kind: .history, sort: .addedDescending, session: rig.session)
        let requests = rig.api.requests.count
        await favorites.removeFromHistory(releaseID: 71)
        await history.removeFromHistory(releaseID: 999)
        XCTAssertEqual(rig.api.requests.count, requests)
    }
}
