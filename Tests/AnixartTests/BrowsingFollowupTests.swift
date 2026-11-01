import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class BrowsingFollowupTests: XCTestCase {
    private func page(_ ids: [Int], status: Int? = 1, favorite: Bool = false) -> String {
        let status = status.map { String($0) } ?? "null"
        let rows = ids.map { "{\"id\":\($0),\"profile_list_status\":\(status),\"is_favorite\":\(favorite)}" }.joined(separator: ",")
        return "{\"code\":0,\"content\":[\(rows)],\"current_page\":0,\"total_page_count\":0,\"total_count\":\(ids.count)}"
    }

    private func detail(status: Int? = 1, favorite: Bool = false, count: Int = 10) -> String {
        let status = status.map { String($0) } ?? "null"
        return "{\"code\":0,\"release\":{\"id\":71,\"title_ru\":\"Тайтл\",\"episodes_released\":4,\"grade\":4.66,\"profile_list_status\":\(status),\"is_favorite\":\(favorite),\"favorites_count\":\(count)}}"
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    @MainActor
    func testHomeSearchFullFilterUsesFilterEndpointAndPreservesDevicePreferences() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let suite = "BrowsingFollowupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = HomePreferences(defaults: defaults)
        prefs.setDefaultTab(.ongoing)
        prefs.rename(customTabTo: "Мой раздел")
        var custom = CustomTabFilter()
        custom.country = "Китай"
        prefs.save(customFilter: custom)
        let stored = defaults.persistentDomain(forName: suite) as NSDictionary?

        let model = CatalogViewModel(session: rig.session, query: "Naruto")
        XCTAssertFalse(model.hasAppliedFilter)
        XCTAssertTrue(rig.api.requests.isEmpty)
        let filter = FilterRequest(sort: .gradeDescending, startYear: 2002, episodeDuration: .upTo30,
                                   country: "Япония", studio: "OLM", source: .manga)
        model.apply(filter: filter)
        XCTAssertTrue(model.hasAppliedFilter)
        XCTAssertFalse(model.isShowingSearch)
        XCTAssertEqual(model.query, "")
        XCTAssertNil(model.currentSearch)
        // HomeSearch passes this exact paginator/viewer into the shared results
        // view, rather than treating these fields as a search/releases body.
        _ = FilteredReleasesView(filter: model.filter, title: "Результаты фильтра", viewer: model.viewer, paginator: model.browse)
        rig.api.enqueue("/filter/0", json: page([201]))
        await model.browse.loadFirstPageIfNeeded()
        let request = try XCTUnwrap(rig.api.requests(to: "/filter/0").first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(try body(request)["studio"] as? String, "OLM")
        XCTAssertEqual(try body(request)["source"] as? String, "Манга")
        XCTAssertEqual(try body(request)["episode_duration_from"] as? Int, 11)
        XCTAssertNil(try body(request)["query"])
        XCTAssertTrue(rig.api.requests(to: "/search/releases/0").isEmpty)
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, stored)
        XCTAssertEqual(HomePreferences(defaults: defaults).customFilter, custom)
        XCTAssertEqual(HomePreferences(defaults: defaults).defaultTab, .ongoing)
    }

    @MainActor
    func testExplicitSameFilterApplyRetiresInFlightSearchAndKeepsFilteredRows() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let model = CatalogViewModel(session: rig.session, filter: FilterRequest(country: "Китай"), query: "Naruto")
        let before = model.browse
        let held = rig.api.hold("/search/releases/0")
        defer { held.respond("{}", status: 500) }
        let searching = Task { await model.search() }
        defer { searching.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        let retired = try XCTUnwrap(model.currentSearch)
        model.apply(filter: FilterRequest(country: " Китай "))
        XCTAssertFalse(model.browse === before)
        XCTAssertFalse(model.isShowingSearch)
        XCTAssertNil(model.currentSearch)
        rig.api.enqueue("/filter/0", json: page([201]))
        await model.browse.loadFirstPageIfNeeded()
        held.respond(#"{"code":0,"related":{"id":999,"name_ru":"Old"},"releases":[{"id":333}]}"#)
        await searching.value
        XCTAssertEqual(model.browse.items.map(\.id), [201])
        XCTAssertTrue(retired.items.isEmpty)
        XCTAssertNil(retired.related)
        let requests = rig.api.requests.count
        await retired.reload()
        await retired.retry()
        await retired.loadNextPage()
        XCTAssertEqual(rig.api.requests.count, requests)
    }

    @MainActor
    func testChangedFilterApplyClearsLoadedSuggestionAndRejectsLateRefresh() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let model = CatalogViewModel(session: rig.session, query: "Naruto")
        rig.api.enqueue("/search/releases/0", json: #"{"code":0,"related":{"id":267},"releases":[{"id":71}]}"#)
        await model.search()
        let retired = try XCTUnwrap(model.currentSearch)
        XCTAssertEqual(retired.related?.id, 267)
        let held = rig.api.hold("/search/releases/0")
        defer { held.respond("{}", status: 500) }
        let oldRefresh = Task { await retired.reload() }
        defer { oldRefresh.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        model.apply(filter: FilterRequest(status: .ongoing, country: "Япония"))
        rig.api.enqueue("/filter/0", json: page([202]))
        await model.browse.loadFirstPageIfNeeded()
        held.respond(#"{"code":0,"related":{"id":999},"releases":[{"id":333}]}"#)
        await oldRefresh.value
        XCTAssertNil(model.currentSearch)
        XCTAssertEqual(model.browse.items.map(\.id), [202])
        let request = try XCTUnwrap(rig.api.requests(to: "/filter/0").first)
        XCTAssertEqual(try body(request)["status_id"] as? Int, 2)
        XCTAssertTrue(retired.items.isEmpty)
        XCTAssertNil(retired.related)
    }

    @MainActor
    func testGeneralFilterResetAndStaleApplyDoNotDispatchSearchOrTouchHomePrefs() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let suite = "BrowsingFollowupReset.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = HomePreferences(defaults: defaults)
        prefs.setDefaultTab(.donghua)
        let model = CatalogViewModel(session: rig.session, filter: FilterRequest(country: "Китай"), query: "Naruto")
        rig.api.enqueue("/search/releases/0", json: #"{"code":0,"related":{"id":267},"releases":[{"id":71}]}"#)
        await model.search()
        let requests = rig.api.requests.count
        model.resetFilter()
        XCTAssertEqual(model.query, "Naruto")
        XCTAssertEqual(model.currentSearch?.related?.id, 267)
        XCTAssertFalse(model.hasAppliedFilter)
        XCTAssertEqual(model.filter, FilterRequest())
        XCTAssertEqual(rig.api.requests.count, requests)
        model.apply(filter: FilterRequest(startYear: 2026, endYear: 2002))
        XCTAssertEqual(model.query, "Naruto")
        XCTAssertFalse(model.hasAppliedFilter)
        try await rig.signIn(token: "later-viewer")
        let afterLogin = rig.api.requests.count
        model.apply(filter: FilterRequest(country: "Япония"))
        await model.browse.loadFirstPageIfNeeded()
        XCTAssertEqual(rig.api.requests.count, afterLogin)
        XCTAssertEqual(model.query, "Naruto")
        XCTAssertEqual(HomePreferences(defaults: defaults).defaultTab, .donghua)
        XCTAssertNil(HomePreferences(defaults: defaults).customFilter)
    }

    @MainActor
    func testHomeOverflowFavouriteRequiresAcknowledgementAndRefreshesOwnFeed() async throws {
        for unconfirmed in ["{}", #"{"code":null}"#, #"{"code":2}"#] {
            let rig = ProfileTestRig()
            try await rig.signIn()
            let feed = ReleaseFeedModel(filter: FilterRequest(), session: rig.session)
            rig.api.enqueue("/filter/0", json: page([71]))
            await feed.paginator.loadFirstPageIfNeeded()
            rig.api.enqueue("/release/71", json: detail())
            await feed.loadActionRelease(releaseID: 71)
            XCTAssertEqual(feed.actionRelease?.titleRu, "Тайтл")
            XCTAssertEqual(feed.actionRelease?.episodeProgressText, "4 из ? эп")
            XCTAssertEqual(feed.actionRelease?.ratingText, "4.7")
            XCTAssertEqual(rig.api.requests(to: "/release/71").count, 1)
            XCTAssertTrue(rig.api.requests(to: "/profile/42").isEmpty)
            rig.api.enqueue("/favorite/add/71", json: unconfirmed)
            let failed = await feed.toggleFavorite(releaseID: 71)
            XCTAssertFalse(failed)
            XCTAssertEqual(feed.actionRelease?.isFavorite, false)
            XCTAssertEqual(feed.paginator.items.first?.isFavorite, false)
            XCTAssertNotNil(feed.actionError)
            XCTAssertEqual(rig.api.requests(to: "/filter/0").count, 1)
            rig.api.enqueue("/favorite/add/71", json: #"{"code":0}"#)
            rig.api.enqueue("/filter/0", json: page([71], favorite: true))
            rig.api.enqueue("/release/71", json: detail(favorite: true, count: 97))
            let changed = await feed.toggleFavorite(releaseID: 71)
            XCTAssertTrue(changed)
            XCTAssertEqual(feed.actionRelease?.favoriteCount, 97)
            XCTAssertEqual(feed.actionRelease?.isFavorite, true)
            XCTAssertEqual(feed.paginator.items.first?.isFavorite, true)
            XCTAssertNil(feed.actionError)
            XCTAssertEqual(rig.api.requests(to: "/profile/42").count, 1)
        }
    }

    @MainActor
    func testCurrentHomeStatusIsNoOpWithoutInvalidatingPendingPageOrBaseline() async throws {
        let statuses: [Int?] = [nil, 1, 2, 3, 4, 5]
        for status in statuses {
            let rig = ProfileTestRig()
            try await rig.signIn()
            let feed = ReleaseFeedModel(filter: FilterRequest(), session: rig.session)
            rig.api.enqueue("/filter/0", json: page(Array(71...95), status: status))
            await feed.paginator.loadFirstPageIfNeeded()
            rig.api.enqueue("/release/71", json: detail(status: status))
            await feed.loadActionRelease(releaseID: 71)
            let held = rig.api.hold("/filter/1")
            defer { held.respond("{}", status: 500) }
            let next = Task { await feed.paginator.loadNextPage() }
            defer { next.cancel() }
            await fulfillment(of: [held.arrived], timeout: 5)
            let rows = feed.paginator.items
            let selected = feed.actionRelease
            let total = feed.paginator.totalCount
            let requests = rig.api.requests.count
            let unchanged = await feed.setList(status.flatMap(ProfileListStatus.init(rawValue:)), releaseID: 71)
            XCTAssertTrue(unchanged)
            XCTAssertEqual(feed.paginator.items, rows)
            XCTAssertEqual(feed.actionRelease, selected)
            XCTAssertEqual(feed.paginator.totalCount, total)
            XCTAssertEqual(feed.paginator.state, .loading)
            XCTAssertFalse(feed.isPerformingAction)
            XCTAssertEqual(rig.api.requests.count, requests)
            held.respond(page([96], status: status))
            await next.value
            XCTAssertEqual(feed.paginator.items.map(\.id), Array(71...96))
            XCTAssertFalse(feed.paginator.hasMore)
        }
    }

    @MainActor
    func testHomeMenuRebasesExcludedStatusAndFavouriteDoesNotReinsertIt() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let feed = ReleaseFeedModel(filter: FilterRequest(profileListExclusions: [.completed]), session: rig.session)
        rig.api.enqueue("/filter/0", json: page(Array(71...95)))
        await feed.paginator.loadFirstPageIfNeeded()
        rig.api.enqueue("/release/71", json: detail())
        await feed.loadActionRelease(releaseID: 71)
        let held = rig.api.hold("/filter/1")
        defer { held.respond("{}", status: 500) }
        let next = Task { await feed.paginator.loadNextPage() }
        defer { next.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        rig.api.enqueue("/profile/list/add/3/71", json: #"{"code":0}"#)
        rig.api.enqueue("/filter/0", json: page([72, 73]))
        rig.api.enqueue("/release/71", json: detail(status: 3))
        let filed = await feed.setList(.completed, releaseID: 71)
        XCTAssertTrue(filed)
        held.respond(page(Array(71...95)))
        await next.value
        XCTAssertEqual(feed.paginator.items.map(\.id), [72, 73])
        XCTAssertEqual(feed.actionRelease?.profileListStatus, 3)
        let count = rig.api.requests.count
        let same = await feed.setList(.completed, releaseID: 71)
        XCTAssertTrue(same)
        XCTAssertEqual(rig.api.requests.count, count)
        rig.api.enqueue("/favorite/add/71", json: #"{"code":0}"#)
        rig.api.enqueue("/filter/0", json: page([72, 73]))
        rig.api.enqueue("/release/71", json: detail(status: 3, favorite: true))
        let favorited = await feed.toggleFavorite(releaseID: 71)
        XCTAssertTrue(favorited)
        XCTAssertEqual(feed.actionRelease?.isFavorite, true)
        XCTAssertEqual(feed.actionRelease?.profileListStatus, 3)
        XCTAssertEqual(feed.paginator.items.map(\.id), [72, 73])
    }

    @MainActor
    func testHomeMenuGuestAndLateOldViewerWriteNeverMutateLaterAccount() async throws {
        let guestRig = ProfileTestRig()
        await guestRig.session.restore()
        let guest = ReleaseFeedModel(filter: FilterRequest(), session: guestRig.session)
        guestRig.api.enqueue("/filter/0", json: page([71], status: nil))
        guestRig.api.enqueue("/release/71", json: detail(status: nil))
        await guest.paginator.loadFirstPageIfNeeded()
        await guest.loadActionRelease(releaseID: 71)
        let guestNoOp = await guest.setList(nil, releaseID: 71)
        XCTAssertTrue(guestNoOp)
        XCTAssertFalse(guestRig.session.isPresentingAuth, "An unchanged guest status does not need login")
        let guestChanged = await guest.toggleFavorite(releaseID: 71)
        XCTAssertFalse(guestChanged)
        XCTAssertTrue(guestRig.session.isPresentingAuth)
        XCTAssertEqual(guestRig.api.requests.count, 2)
        XCTAssertEqual(guest.actionRelease?.isFavorite, false)

        let rig = ProfileTestRig()
        try await rig.signIn(token: "first")
        let feed = ReleaseFeedModel(filter: FilterRequest(), session: rig.session)
        rig.api.enqueue("/filter/0", json: page([71]))
        rig.api.enqueue("/release/71", json: detail())
        await feed.paginator.loadFirstPageIfNeeded()
        await feed.loadActionRelease(releaseID: 71)
        let held = rig.api.hold("/favorite/add/71")
        defer { held.respond("{}", status: 500) }
        let mutation = Task { await feed.toggleFavorite(releaseID: 71) }
        defer { mutation.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        let second = await feed.setList(.plan, releaseID: 71)
        XCTAssertFalse(second)
        try await rig.signIn(token: "second")
        held.respond(#"{"code":0}"#)
        let applied = await mutation.value
        XCTAssertFalse(applied)
        XCTAssertNil(feed.actionRelease)
        XCTAssertEqual(feed.paginator.items.first?.isFavorite, false)
        XCTAssertNil(feed.actionError)
        XCTAssertEqual(rig.api.requests(to: "/filter/0").count, 1)
        let count = rig.api.requests.count
        let stale = await feed.toggleFavorite(releaseID: 71)
        XCTAssertFalse(stale)
        XCTAssertEqual(rig.api.requests.count, count)
    }

    @MainActor
    func testHomeFavouriteAcknowledgementSurvivesSupplementaryReadFailureAndReadOnlyRetry() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let feed = ReleaseFeedModel(filter: FilterRequest(), session: rig.session)
        rig.api.enqueue("/filter/0", json: page([71]))
        rig.api.enqueue("/release/71", json: detail())
        await feed.paginator.loadFirstPageIfNeeded()
        await feed.loadActionRelease(releaseID: 71)
        rig.api.enqueue("/favorite/add/71", json: #"{"code":0}"#)
        rig.api.enqueue("/filter/0", json: page([71], favorite: true))
        rig.api.enqueue("/release/71", json: #"{"code":2}"#)
        let acknowledged = await feed.toggleFavorite(releaseID: 71)
        XCTAssertTrue(acknowledged)
        XCTAssertEqual(feed.actionRelease?.isFavorite, true)
        XCTAssertEqual(feed.actionRelease?.favoriteCount, 10, "No guessed global +1")
        XCTAssertEqual(feed.paginator.items.first?.isFavorite, true)
        XCTAssertNotNil(feed.actionLoadError)
        XCTAssertNil(feed.actionError)
        let beforeRetry = rig.api.requests.count
        let staleSnapshotWrite = await feed.toggleFavorite(releaseID: 71)
        XCTAssertFalse(staleSnapshotWrite, "A failed fresh read cannot authorize a new write from its old snapshot")
        XCTAssertEqual(rig.api.requests.count, beforeRetry)
        rig.api.enqueue("/release/71", json: detail(favorite: true, count: 88))
        await feed.loadActionRelease(releaseID: 71)
        XCTAssertEqual(feed.actionRelease?.favoriteCount, 88)
        XCTAssertNil(feed.actionLoadError)
        XCTAssertEqual(rig.api.requests(to: "/favorite/add/71").count, 1)
    }
}
