import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class RawPagingRegressionTests: XCTestCase {
    private func page(_ ids: [Int], current: Int = 0, pages: Int? = 0, total: Int? = nil) -> String {
        let rows = ids.map { "{\"id\":\($0)}" }.joined(separator: ",")
        let metadata = pages.map { ",\"total_page_count\":\($0)" } ?? ""
        return "{\"code\":0,\"content\":[\(rows)],\"current_page\":\(current),\"total_count\":\(total ?? ids.count)\(metadata)}"
    }

    @MainActor
    func testRelatedRaw25Then2KeepsLastReleasesWithZeroPageMetadata() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let list = BrowsingPaginators.related(relatedID: 17, viewer: rig.session.viewerKey, session: rig.session)
        rig.api.enqueue("/related/17/0", json: page(Array(1...25)))
        rig.api.enqueue("/related/17/1", json: page([26, 27], current: 1, total: 27))
        await list.loadFirstPageIfNeeded()
        XCTAssertTrue(list.hasMore)
        await list.loadNextPage()
        XCTAssertEqual(list.items.map(\.id), Array(1...27))
        XCTAssertEqual(list.totalCount, 27)
        XCTAssertFalse(list.hasMore)
        await list.loadNextPage()
        XCTAssertTrue(rig.api.requests(to: "/related/17/2").isEmpty)
        XCTAssertEqual(rig.api.requests.first?.value(forHTTPHeaderField: "API-Version"), "v2")
    }

    @MainActor
    func testFilterFeedsAndCatalogueUseRequestedIndexDespiteCurrentPageAlwaysZero() async {
        for homeFeed in [true, false] {
            let rig = ProfileTestRig()
            await rig.session.restore()
            let list = homeFeed ? ReleaseFeedModel(filter: FilterRequest(), session: rig.session).paginator
                                : CatalogViewModel(session: rig.session).browse
            rig.api.enqueue("/filter/0", json: page(Array(1...25), total: 25))
            rig.api.enqueue("/filter/1", json: page(Array(26...50), current: 0, total: 25))
            rig.api.enqueue("/filter/2", json: page([51, 52], current: 0, total: 25))
            await list.loadFirstPageIfNeeded()
            await list.loadNextPage()
            XCTAssertEqual(list.items.count, 50)
            XCTAssertTrue(list.hasMore)
            await list.loadNextPage()
            XCTAssertEqual(list.items.map(\.id), Array(1...52))
            XCTAssertFalse(list.hasMore)
            XCTAssertEqual(list.totalCount, 25, "Keep server metadata without presenting it as a final paging boundary")
            await list.loadNextPage()
            XCTAssertEqual(rig.api.requests(to: "/filter/1").count, 1)
            XCTAssertTrue(rig.api.requests(to: "/filter/3").isEmpty)
        }
    }

    @MainActor
    func testVideoAllAndCategoryUseRawPagesNotCumulativeTotalCount() async {
        let categories: [Int?] = [nil, 9]
        for category in categories {
            let rig = ProfileTestRig()
            await rig.session.restore()
            let root = category.map { "/video/release/71/category/\($0)" } ?? "/video/release/71"
            let model = ReleaseVideosViewModel(releaseID: 71, categoryID: category, viewer: rig.session.viewerKey, session: rig.session)
            rig.api.enqueue(root + "/0", json: page(Array(1...25), total: 25))
            rig.api.enqueue(root + "/1", json: page(Array(26...50), current: 1, total: 50))
            rig.api.enqueue(root + "/2", json: page([51], current: 2, total: 51))
            await model.paginator.loadFirstPageIfNeeded()
            await model.paginator.loadNextPage()
            XCTAssertTrue(model.paginator.hasMore)
            XCTAssertEqual(model.paginator.totalCount, 50)
            await model.paginator.loadNextPage()
            XCTAssertEqual(model.paginator.items.count, 51)
            XCTAssertFalse(model.paginator.hasMore)
            await model.paginator.loadNextPage()
            XCTAssertTrue(rig.api.requests(to: root + "/3").isEmpty)
        }
        let rig = ProfileTestRig()
        await rig.session.restore()
        let short = ReleaseVideosViewModel(releaseID: 71, categoryID: 1, viewer: rig.session.viewerKey, session: rig.session)
        rig.api.enqueue("/video/release/71/category/1/0", json: page([1, 2]))
        await short.paginator.loadFirstPageIfNeeded()
        await short.paginator.loadNextPage()
        XCTAssertEqual(rig.api.requests(to: "/video/release/71/category/1/0").count, 1)
        XCTAssertTrue(rig.api.requests(to: "/video/release/71/category/1/1").isEmpty)
    }

    @MainActor
    func testPositiveCollectionLastIndexMetadataDoesNotTruncateFinalPage() async {
        for source in 0...2 {
            let rig = ProfileTestRig()
            await rig.session.restore()
            let viewer = rig.session.viewerKey
            let paths = ["/collection/all", "/collection/all/release/71", "/collection/17/releases"]
            rig.api.enqueue(paths[source] + "/0", json: page(Array(1...25), pages: 1, total: 49))
            rig.api.enqueue(paths[source] + "/1", json: page(Array(26...49), current: 1, pages: 1, total: 49))
            if source == 2 {
                let list = BrowsingPaginators.collectionReleases(collectionID: 17, viewer: viewer, session: rig.session)
                await list.loadFirstPageIfNeeded()
                XCTAssertTrue(list.hasMore)
                await list.loadNextPage()
                XCTAssertEqual(list.items.count, 49)
                XCTAssertFalse(list.hasMore)
                await list.loadNextPage()
            } else {
                let list = source == 0 ? BrowsingPaginators.publicCollections(viewer: viewer, session: rig.session)
                                       : BrowsingPaginators.releaseCollections(releaseID: 71, viewer: viewer, session: rig.session)
                await list.loadFirstPageIfNeeded()
                XCTAssertTrue(list.hasMore)
                await list.loadNextPage()
                XCTAssertEqual(list.items.count, 49)
                XCTAssertFalse(list.hasMore)
                await list.loadNextPage()
            }
            XCTAssertEqual(rig.api.requests(to: paths[source] + "/1").count, 1)
            XCTAssertTrue(rig.api.requests(to: paths[source] + "/2").isEmpty)
        }
    }

    @MainActor
    func testFullRawDuplicatePagesDoNotBecomeFalseLastPages() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let list = BrowsingPaginators.related(relatedID: 17, viewer: rig.session.viewerKey, session: rig.session)
        rig.api.enqueue("/related/17/0", json: page(Array(repeating: 1, count: 25), pages: 1))
        rig.api.enqueue("/related/17/1", json: page(Array(repeating: 2, count: 25), current: 0, pages: 1))
        rig.api.enqueue("/related/17/2", json: page([2, 3], current: 0, pages: 1))
        await list.loadFirstPageIfNeeded()
        XCTAssertEqual(list.items.map(\.id), [1])
        XCTAssertTrue(list.hasMore)
        await list.loadNextPage()
        XCTAssertEqual(list.items.map(\.id), [1, 2])
        XCTAssertTrue(list.hasMore)
        await list.loadNextPage()
        XCTAssertEqual(list.items.map(\.id), [1, 2, 3])
        XCTAssertFalse(list.hasMore)
    }

    @MainActor
    func testRawNextPageFailureRetriesSameRequestedPageWithoutReloadingZero() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let list = BrowsingPaginators.related(relatedID: 17, viewer: rig.session.viewerKey, session: rig.session)
        rig.api.enqueue("/related/17/0", json: page(Array(1...25)))
        rig.api.enqueue("/related/17/1", json: #"{"code":2}"#)
        rig.api.enqueue("/related/17/1", json: page([26, 27], current: 0))
        await list.loadFirstPageIfNeeded()
        await list.loadNextPage()
        XCTAssertEqual(list.failedPage, 1)
        XCTAssertEqual(list.items.count, 25)
        await list.loadNextPage()
        XCTAssertEqual(rig.api.requests(to: "/related/17/1").count, 1)
        await list.retry()
        XCTAssertEqual(list.items.count, 27)
        XCTAssertNil(list.errorMessage)
        XCTAssertFalse(list.hasMore)
        XCTAssertEqual(rig.api.requests(to: "/related/17/0").count, 1)
        XCTAssertEqual(rig.api.requests(to: "/related/17/1").count, 2)
    }

    @MainActor
    func testCancelledRawFirstAndNextPagesRemainRetriableAtSameIndex() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let list = BrowsingPaginators.related(relatedID: 17, viewer: rig.session.viewerKey, session: rig.session)
        let first = rig.api.hold("/related/17/0")
        defer { first.respond("{}", status: 500) }
        let loading = Task { await list.loadFirstPageIfNeeded() }
        defer { loading.cancel() }
        await fulfillment(of: [first.arrived], timeout: 5)
        loading.cancel()
        await loading.value
        XCTAssertEqual(list.state, .idle)
        XCTAssertNil(list.errorMessage)
        rig.api.enqueue("/related/17/0", json: page(Array(1...25)))
        await list.loadFirstPageIfNeeded()
        let second = rig.api.hold("/related/17/1")
        defer { second.respond("{}", status: 500) }
        let next = Task { await list.loadNextPage() }
        defer { next.cancel() }
        await fulfillment(of: [second.arrived], timeout: 5)
        next.cancel()
        await next.value
        XCTAssertEqual(list.items.count, 25)
        XCTAssertEqual(list.state, .idle)
        XCTAssertNil(list.errorMessage)
        rig.api.enqueue("/related/17/1", json: page([26]))
        await list.loadNextPage()
        XCTAssertEqual(list.items.count, 26)
        XCTAssertFalse(list.hasMore)
        XCTAssertEqual(rig.api.requests(to: "/related/17/1").count, 2)
    }

    @MainActor
    func testLatestRawRefreshRejectsOlderFullNextPageAndKeepsShortEnd() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let list = BrowsingPaginators.related(relatedID: 17, viewer: rig.session.viewerKey, session: rig.session)
        rig.api.enqueue("/related/17/0", json: page(Array(1...25)))
        await list.loadFirstPageIfNeeded()
        let held = rig.api.hold("/related/17/1")
        defer { held.respond("{}", status: 500) }
        let next = Task { await list.loadNextPage() }
        defer { next.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        rig.api.enqueue("/related/17/0", json: page([201, 202], pages: 100))
        await list.reload()
        held.respond(page(Array(26...50), current: 0))
        await next.value
        XCTAssertEqual(list.items.map(\.id), [201, 202])
        XCTAssertFalse(list.hasMore)
        XCTAssertNil(list.errorMessage)
        await list.loadNextPage()
        XCTAssertEqual(rig.api.requests(to: "/related/17/1").count, 1)
    }

    @MainActor
    func testDefaultMetadataAndLegacyMissingCountStrategiesStayUnchanged() async {
        let rig = ProfileTestRig()
        let client = rig.client
        let normal = Paginator<Release> { page in
            try await client.send(Endpoint<PageableResponse<Release>>(path: "metadata/\(page)", auth: .none))
        }
        rig.api.enqueue("/metadata/0", json: page([1, 2], pages: 2))
        rig.api.enqueue("/metadata/1", json: page([3], current: 1, pages: 2))
        await normal.loadFirstPageIfNeeded()
        XCTAssertTrue(normal.hasMore, "Default does not adopt raw-size 25")
        await normal.loadNextPage()
        XCTAssertEqual(normal.items.map(\.id), [1, 2, 3])
        XCTAssertFalse(normal.hasMore)

        let zero = Paginator<Release> { page in
            try await client.send(Endpoint<PageableResponse<Release>>(path: "zero/\(page)", auth: .none))
        }
        rig.api.enqueue("/zero/0", json: page(Array(1...25), pages: 0))
        await zero.loadFirstPageIfNeeded()
        await zero.loadNextPage()
        XCTAssertFalse(zero.hasMore)
        XCTAssertTrue(rig.api.requests(to: "/zero/1").isEmpty)

        let legacy = Paginator<Release>(continuesWithoutPageCount: true) { page in
            try await client.send(Endpoint<PageableResponse<Release>>(path: "legacy/\(page)", auth: .none))
        }
        rig.api.enqueue("/legacy/0", json: page([1], pages: nil))
        rig.api.enqueue("/legacy/1", json: page([], pages: nil))
        await legacy.loadFirstPageIfNeeded()
        XCTAssertTrue(legacy.hasMore)
        await legacy.loadNextPage()
        XCTAssertFalse(legacy.hasMore)
    }
}
