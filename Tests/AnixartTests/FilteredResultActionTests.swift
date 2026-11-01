import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class FilteredResultActionTests: XCTestCase {
    private func page(_ ids: [Int]) -> String {
        let rows = ids.map { "{\"id\":\($0),\"profile_list_status\":1}" }.joined(separator: ",")
        return "{\"code\":0,\"content\":[\(rows)],\"current_page\":0,\"total_page_count\":0}"
    }

    @MainActor
    func testFilteredSearchActionsRebaseTheDisplayedCataloguePaginator() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let filter = FilterRequest(profileListExclusions: [.completed])
        let catalogue = CatalogViewModel(session: rig.session, filter: filter, hasAppliedFilter: true)
        let feed = ReleaseFeedModel(filter: filter, session: rig.session, paginator: catalogue.browse)
        XCTAssertTrue(feed.paginator === catalogue.browse)

        rig.api.enqueue("/filter/0", json: page(Array(71...95)))
        await catalogue.browse.loadFirstPageIfNeeded()
        rig.api.enqueue("/release/71", json: #"{"code":0,"release":{"id":71,"profile_list_status":1}}"#)
        await feed.loadActionRelease(releaseID: 71)

        let held = rig.api.hold("/filter/1")
        defer { held.respond("{}", status: 500) }
        let next = Task { await catalogue.browse.loadNextPage() }
        defer { next.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)

        rig.api.enqueue("/profile/list/add/3/71", json: #"{"code":0}"#)
        rig.api.enqueue("/filter/0", json: page([72, 73]))
        rig.api.enqueue("/release/71", json: #"{"code":0,"release":{"id":71,"profile_list_status":3}}"#)
        let changed = await feed.setList(.completed, releaseID: 71)
        XCTAssertTrue(changed)
        held.respond(page(Array(71...95)))
        await next.value

        XCTAssertTrue(feed.paginator === catalogue.browse)
        XCTAssertEqual(catalogue.browse.items.map(\.id), [72, 73])
        XCTAssertFalse(catalogue.browse.hasMore)
        XCTAssertEqual(feed.actionRelease?.profileListStatus, 3)
        XCTAssertEqual(rig.api.requests(to: "/filter/0").count, 2)
    }
}
