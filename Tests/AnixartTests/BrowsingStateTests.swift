import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class BrowsingStateTests: XCTestCase {
    private func page(_ ids: [Int], index: Int = 0, pages: Int = 1, status: Int? = nil) -> String {
        let list = status.map { ",\"profile_list_status\":\($0)" } ?? ""
        let rows = ids.map { "{\"id\":\($0)\(list)}" }.joined(separator: ",")
        return "{\"code\":0,\"content\":[\(rows)],\"current_page\":\(index),\"total_page_count\":\(pages)}"
    }

    private func searchPage(_ ids: [Int], relatedID: Int? = nil) -> String {
        let rows = ids.map { "{\"id\":\($0)}" }.joined(separator: ",")
        let related = relatedID.map { ",\"related\":{\"id\":\($0),\"name_ru\":\"Franchise\"}" } ?? ""
        return "{\"code\":0,\"releases\":[\(rows)]\(related)}"
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    private func token(_ request: URLRequest) -> String? {
        request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == "token" }?.value
    }

    @MainActor
    func testHomePresetsKeepExactSingleConstraintAndDefaultSort() throws {
        let expected: [(HomeTab, String?, Int?, Int?)] = [
            (.anime, "Япония", nil, nil), (.donghua, "Китай", nil, nil),
            (.latest, nil, nil, nil), (.ongoing, nil, 2, nil), (.announced, nil, 3, nil),
            (.finished, nil, 1, nil), (.movies, nil, nil, 2), (.ova, nil, nil, 3)
        ]
        XCTAssertNil(HomeTab.custom.filter)
        for (tab, country, status, category) in expected {
            let filter = try XCTUnwrap(tab.filter)
            XCTAssertEqual(filter.sort, 0)
            XCTAssertEqual(filter.country, country)
            XCTAssertEqual(filter.statusId, status)
            XCTAssertEqual(filter.categoryId, category)
            XCTAssertNil(filter.genres)
            XCTAssertNil(filter.profileListExclusions)
        }
    }

    @MainActor
    func testDeviceDefaultAndCustomFilterPersistIndependently() throws {
        let suite = "BrowsingStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = HomePreferences(defaults: defaults)
        XCTAssertEqual(preferences.defaultTab, .anime)
        preferences.setDefaultTab(.ongoing)
        preferences.rename(customTabTo: "  Мой раздел  ")
        var filter = CustomTabFilter()
        filter.country = "Китай"
        filter.genres = ["драма"]
        preferences.save(customFilter: filter)
        let restored = HomePreferences(defaults: defaults)
        XCTAssertEqual(restored.defaultTab, .ongoing)
        XCTAssertEqual(restored.customTabTitle, "Мой раздел")
        XCTAssertEqual(restored.customFilter, filter)
        restored.save(customFilter: nil)
        XCTAssertEqual(HomePreferences(defaults: defaults).defaultTab, .ongoing)
        XCTAssertEqual(HomePreferences(defaults: defaults).customTabTitle, "Мой раздел")
        XCTAssertNil(HomePreferences(defaults: defaults).customFilter)
    }

    @MainActor
    func testFourFieldCustomFilterDoesNotApplyInvisibleLegacyFullFilterKeys() {
        var filter = CustomTabFilter()
        filter.country = "Китай"
        filter.category = .series
        filter.genres = ["драма", "комедия"]
        filter.profileListExclusions = [.completed]
        // Earlier alphas stored these complete-filter settings in the custom tab.
        filter.status = .ongoing
        filter.types = [9]
        filter.studio = "OLM"
        filter.source = .manga
        filter.startYear = 2002
        filter.episodeDuration = .upTo30
        filter.sort = .gradeDescending
        let request = filter.filterRequest
        XCTAssertEqual(request.country, "Китай")
        XCTAssertEqual(request.categoryId, 1)
        XCTAssertEqual(request.genres, ["драма", "комедия"])
        XCTAssertEqual(request.genresMode, 1)
        XCTAssertEqual(request.profileListExclusions, [3])
        XCTAssertEqual(request.sort, 0)
        XCTAssertNil(request.statusId)
        XCTAssertNil(request.types)
        XCTAssertNil(request.studio)
        XCTAssertNil(request.source)
        XCTAssertNil(request.startYear)
        XCTAssertNil(request.episodeDurationFrom)
        XCTAssertEqual(filter.activeCount, 4)
        XCTAssertEqual(filter.studio, "OLM", "Reading the new request does not erase persisted legacy data")
    }

    @MainActor
    func testGuestFeedOmitsOnlyAccountExclusionsAndNeverWrites() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let filter = FilterRequest(country: "Китай", genres: ["драма"], genresMode: .any, profileListExclusions: [.completed])
        rig.api.enqueue("/filter/0", json: page([71]))
        let feed = ReleaseFeedModel(filter: filter, session: rig.session)
        await feed.paginator.loadFirstPageIfNeeded()
        let request = try XCTUnwrap(rig.api.requests(to: "/filter/0").first)
        let json = try body(request)
        XCTAssertNil(token(request))
        XCTAssertEqual(json["country"] as? String, "Китай")
        XCTAssertEqual(json["genres_mode"] as? Int, 1)
        XCTAssertNil(json["profile_list_exclusions"])
        XCTAssertEqual(feed.filter.profileListExclusions, [3])
        let changed = await feed.setList(.watching, releaseID: 71)
        XCTAssertFalse(changed)
        XCTAssertTrue(rig.session.isPresentingAuth)
        XCTAssertNil(feed.paginator.items.first?.profileListStatus)
        XCTAssertEqual(rig.api.requests.count, 1)
    }

    @MainActor
    func testHomeListPickerRequiresAcknowledgementAndRetriesWithoutLosingStatus() async throws {
        for unconfirmed in ["{}", #"{"code":null}"#, #"{"code":2}"#] {
            let rig = ProfileTestRig()
            try await rig.signIn()
            rig.api.enqueue("/filter/0", json: page([71], status: 1))
            let feed = ReleaseFeedModel(filter: FilterRequest(), session: rig.session)
            await feed.paginator.loadFirstPageIfNeeded()
            rig.api.enqueue("/profile/list/add/3/71", json: unconfirmed)
            let failed = await feed.setList(.completed, releaseID: 71)
            XCTAssertFalse(failed)
            XCTAssertEqual(feed.paginator.items.first?.profileListStatus, 1)
            XCTAssertNotNil(feed.actionError)
            XCTAssertFalse(feed.isPerformingAction)
            XCTAssertEqual(rig.api.requests(to: "/filter/0").count, 1)
            XCTAssertTrue(rig.api.requests(to: "/profile/42").isEmpty)

            rig.api.enqueue("/profile/list/add/3/71", json: #"{"code":0}"#)
            rig.api.enqueue("/filter/0", json: page([71], status: 3))
            let succeeded = await feed.setList(.completed, releaseID: 71)
            XCTAssertTrue(succeeded)
            XCTAssertEqual(feed.paginator.items.first?.profileListStatus, 3)
            XCTAssertNil(feed.actionError)
            XCTAssertEqual(rig.api.requests(to: "/profile/42").count, 1)
        }
    }

    @MainActor
    func testHomeListPickerReallyRemovesTheKnownOldStatus() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "owner")
        rig.api.enqueue("/filter/0", json: page([71], status: 4))
        let feed = ReleaseFeedModel(filter: FilterRequest(), session: rig.session)
        await feed.paginator.loadFirstPageIfNeeded()
        rig.api.enqueue("/profile/list/delete/4/71", json: #"{"code":0}"#)
        rig.api.enqueue("/filter/0", json: page([71]))
        let changed = await feed.setList(nil, releaseID: 71)
        XCTAssertTrue(changed)
        XCTAssertNil(feed.paginator.items.first?.profileListStatus)
        XCTAssertEqual(token(try XCTUnwrap(rig.api.requests(to: "/profile/list/delete/4/71").first)), "owner")
        XCTAssertTrue(rig.api.requests(to: "/profile/list/add/4/71").isEmpty)
    }

    @MainActor
    func testHomeMutationRebasesExcludedResultsAndRejectsAnOlderNextPage() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        rig.api.enqueue("/filter/0", json: page(Array(71...95), pages: 0, status: 1))
        let feed = ReleaseFeedModel(filter: FilterRequest(profileListExclusions: [.completed]), session: rig.session)
        await feed.paginator.loadFirstPageIfNeeded()
        let held = rig.api.hold("/filter/1")
        defer { held.respond("{}", status: 500) }
        let next = Task { await feed.paginator.loadNextPage() }
        defer { next.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        rig.api.enqueue("/profile/list/add/3/71", json: #"{"code":0}"#)
        rig.api.enqueue("/filter/0", json: page([72, 73]))
        let changed = await feed.setList(.completed, releaseID: 71)
        XCTAssertTrue(changed)
        held.respond(page([71, 74], index: 1, pages: 2, status: 1))
        await next.value
        XCTAssertEqual(feed.paginator.items.map(\.id), [72, 73])
        XCTAssertFalse(feed.paginator.hasMore)
    }

    @MainActor
    func testOldHomePickerCannotUseNewLoginOrCommitItsLateResponse() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "first")
        rig.api.enqueue("/filter/0", json: page([71], status: 1))
        let feed = ReleaseFeedModel(filter: FilterRequest(), session: rig.session)
        await feed.paginator.loadFirstPageIfNeeded()
        let held = rig.api.hold("/profile/list/add/3/71")
        defer { held.respond("{}", status: 500) }
        let mutation = Task { await feed.setList(.completed, releaseID: 71) }
        defer { mutation.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        let concurrent = await feed.setList(.plan, releaseID: 71)
        XCTAssertFalse(concurrent)
        try await rig.signIn(token: "second")
        held.respond(#"{"code":0}"#)
        let applied = await mutation.value
        XCTAssertFalse(applied)
        XCTAssertFalse(feed.hasCurrentViewer)
        XCTAssertEqual(feed.paginator.items.first?.profileListStatus, 1)
        XCTAssertNil(feed.actionError)
        XCTAssertEqual(token(try XCTUnwrap(held.request)), "first")
        XCTAssertEqual(rig.api.requests(to: "/filter/0").count, 1)
        let requests = rig.api.requests.count
        let stale = await feed.setList(.plan, releaseID: 71)
        XCTAssertFalse(stale)
        XCTAssertEqual(rig.api.requests.count, requests)
    }

    @MainActor
    func testSearchPaginatesByRaw25CountDeduplicatesAndKeepsFirstFranchise() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        rig.api.enqueue("/search/releases/0", json: searchPage(Array(1...24) + [24], relatedID: 17))
        rig.api.enqueue("/search/releases/1", json: searchPage([24, 25], relatedID: 999))
        let results = ReleaseSearchModel(query: "Naruto", session: rig.session)
        await results.loadFirstPageIfNeeded(debounce: false)
        XCTAssertEqual(results.items.count, 24)
        XCTAssertTrue(results.hasMore)
        await results.loadNextPage()
        XCTAssertEqual(results.items.map(\.id), Array(1...25))
        XCTAssertEqual(results.related?.id, 17)
        XCTAssertFalse(results.hasMore)
        await results.loadNextPage()
        XCTAssertEqual(rig.api.requests(to: "/search/releases/1").count, 1)
    }

    @MainActor
    func testSearchNextPageErrorRetriesSamePageAndKeepsVisibleResults() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        rig.api.enqueue("/search/releases/0", json: searchPage(Array(1...25), relatedID: 17))
        rig.api.enqueue("/search/releases/1", json: #"{"code":2}"#)
        rig.api.enqueue("/search/releases/1", json: searchPage([26]))
        let results = ReleaseSearchModel(query: "Naruto", session: rig.session)
        await results.loadFirstPageIfNeeded(debounce: false)
        await results.loadNextPage()
        XCTAssertEqual(results.failedPage, 1)
        XCTAssertEqual(results.items.count, 25)
        XCTAssertEqual(results.related?.id, 17)
        await results.loadNextPage()
        XCTAssertEqual(rig.api.requests(to: "/search/releases/1").count, 1)
        await results.retry()
        XCTAssertEqual(results.items.count, 26)
        XCTAssertNil(results.errorMessage)
        XCTAssertEqual(rig.api.requests(to: "/search/releases/0").count, 1)
        XCTAssertEqual(rig.api.requests(to: "/search/releases/1").count, 2)
    }

    @MainActor
    func testLateSearchRefreshCannotOverwriteNewRowsOrFranchise() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let held = rig.api.hold("/search/releases/0")
        defer { held.respond("{}", status: 500) }
        let results = ReleaseSearchModel(query: "Naruto", session: rig.session)
        let old = Task { await results.reload() }
        defer { old.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        rig.api.enqueue("/search/releases/0", json: searchPage([2], relatedID: 22))
        await results.reload()
        held.respond(searchPage([1], relatedID: 11))
        await old.value
        XCTAssertEqual(results.items.map(\.id), [2])
        XCTAssertEqual(results.related?.id, 22)
        XCTAssertFalse(results.isLoading)
        XCTAssertNil(results.errorMessage)
    }

    @MainActor
    func testChangedQueryAndScopeHideOldSearchEvenWithoutCancellingItsTask() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let model = CatalogViewModel(session: rig.session)
        model.query = "old"
        let held = rig.api.hold("/search/releases/0")
        defer { held.respond("{}", status: 500) }
        let old = Task { await model.search() }
        defer { old.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        model.query = "\n new \n"
        model.searchScope = .titleOriginal
        XCTAssertNil(model.currentSearch)
        rig.api.enqueue("/search/releases/0", json: searchPage([2], relatedID: 22))
        await model.search()
        held.respond(searchPage([1], relatedID: 11))
        await old.value
        XCTAssertEqual(model.currentSearch?.items.map(\.id), [2])
        XCTAssertEqual(model.currentSearch?.related?.id, 22)
        let request = try XCTUnwrap(rig.api.requests(to: "/search/releases/0").last)
        XCTAssertEqual(try body(request)["query"] as? String, "new")
        XCTAssertEqual(try body(request)["searchBy"] as? Int, 2)
        XCTAssertEqual(request.value(forHTTPHeaderField: "API-Version"), "v2")
        model.query = " \n\t "
        await model.search()
        XCTAssertFalse(model.isShowingSearch)
        XCTAssertNil(model.currentSearch)
        XCTAssertEqual(rig.api.requests(to: "/search/releases/0").count, 2)
    }

    @MainActor
    func testCancelledInitialSearchCanReloadWithoutStuckSpinnerOrFalseError() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let held = rig.api.hold("/search/releases/0")
        defer { held.respond("{}", status: 500) }
        let results = ReleaseSearchModel(query: "Naruto", session: rig.session)
        let load = Task { await results.loadFirstPageIfNeeded(debounce: false) }
        defer { load.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        load.cancel()
        await load.value
        XCTAssertFalse(results.isLoading)
        XCTAssertNil(results.errorMessage)
        rig.api.enqueue("/search/releases/0", json: searchPage([71]))
        await results.loadFirstPageIfNeeded(debounce: false)
        XCTAssertEqual(results.items.map(\.id), [71])
    }

    @MainActor
    func testMissingSearchResultsAreFailureNotNothingFoundAndFranchiseOnlyIsValid() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        rig.api.enqueue("/search/releases/0", json: #"{"code":0}"#)
        let results = ReleaseSearchModel(query: "Naruto", session: rig.session)
        await results.reload()
        XCTAssertNotNil(results.errorMessage)
        XCTAssertEqual(results.failedPage, 0)
        rig.api.enqueue("/search/releases/0", json: searchPage([], relatedID: 17))
        await results.retry()
        XCTAssertNil(results.errorMessage)
        XCTAssertEqual(results.related?.id, 17)
        XCTAssertTrue(results.items.isEmpty)
        XCTAssertFalse(results.hasMore)
    }

    @MainActor
    func testSearchAndBrowseSnapshotsCannotReadWithALaterSession() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "first")
        let model = CatalogViewModel(session: rig.session, query: "Naruto")
        let results = ReleaseSearchModel(query: "Naruto", session: rig.session)
        try await rig.signIn(token: "second")
        let requests = rig.api.requests.count
        await model.browse.loadFirstPageIfNeeded()
        await results.reload()
        await model.search()
        XCTAssertFalse(model.hasCurrentViewer)
        XCTAssertNil(model.currentSearch)
        XCTAssertFalse(results.hasCurrentViewer)
        XCTAssertEqual(rig.api.requests.count, requests)
    }

    @MainActor
    func testFilterReplacementDoesNotMixOldPagesAndRejectsInvalidYearRange() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let model = CatalogViewModel(session: rig.session)
        let oldBrowse = model.browse
        let held = rig.api.hold("/filter/0")
        defer { held.respond("{}", status: 500) }
        let old = Task { await oldBrowse.reload() }
        defer { old.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        model.apply(filter: FilterRequest(country: "Китай"))
        rig.api.enqueue("/filter/0", json: page([2]))
        await model.browse.loadFirstPageIfNeeded()
        held.respond(page([1]))
        await old.value
        XCTAssertEqual(model.browse.items.map(\.id), [2])
        XCTAssertEqual(model.filter.country, "Китай")
        let current = model.browse
        model.apply(filter: FilterRequest(startYear: 2026, endYear: 2002))
        XCTAssertTrue(model.browse === current)
        XCTAssertEqual(model.filter.country, "Китай")
    }

    @MainActor
    func testVideoCategoryModelUsesPublicEndpointAndViewerSnapshot() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "first")
        let viewer = rig.session.viewerKey
        rig.api.enqueue("/video/release/71/category/9/0", json: page([1]))
        let model = ReleaseVideosViewModel(releaseID: 71, categoryID: 9, viewer: viewer, session: rig.session)
        await model.paginator.loadFirstPageIfNeeded()
        XCTAssertEqual(model.paginator.items.map(\.id), [1])
        XCTAssertNil(token(try XCTUnwrap(rig.api.requests(to: "/video/release/71/category/9/0").first)))
        try await rig.signIn(token: "second")
        let requests = rig.api.requests.count
        await model.paginator.reload()
        XCTAssertEqual(rig.api.requests.count, requests)
    }

    func testRelatedSourceContextKeepsSearchHeaderSeparateFromReleaseList() throws {
        let related = try profileTestDecode(Related.self, #"{"id":17,"name_ru":"Наруто","description":"Произведение"}"#)
        XCTAssertTrue(RelatedReleasesContext.franchise.showsFranchiseHeader)
        XCTAssertEqual(RelatedReleasesContext.franchise.title(for: related), "Наруто")
        XCTAssertFalse(RelatedReleasesContext.release(71).showsFranchiseHeader)
        XCTAssertEqual(RelatedReleasesContext.release(71).title(for: related), "Связанные релизы")
    }

    @MainActor
    func testPreloadedReleaseKeepsVisibleDataButReportsFailedExtendedRead() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let release = try profileTestDecode(Release.self, #"{"id":71,"title_ru":"Наруто"}"#)
        let model = ReleaseDetailViewModel(releaseID: 71, preloaded: release, session: rig.session)
        rig.api.enqueue("/release/71", json: #"{"code":2}"#)
        await model.load()
        XCTAssertEqual(model.release?.displayTitle, "Наруто")
        XCTAssertNotNil(model.errorMessage)
        rig.api.enqueue("/release/71", json: #"{"code":0,"release":{"id":71,"title_ru":"Наруто","vote_count":5}}"#)
        await model.load()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.release?.voteCount, 5)
    }

    @MainActor
    func testAcknowledgedVoteSurvivesFailedAggregateReloadAndMissingVoteCannotBeRemoved() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let release = try profileTestDecode(Release.self, #"{"id":71,"your_vote":2,"grade":4.66}"#)
        let model = ReleaseDetailViewModel(releaseID: 71, preloaded: release, session: rig.session)
        rig.api.enqueue("/release/vote/add/71/5", json: #"{"code":0}"#)
        rig.api.enqueue("/release/71", json: #"{"code":2}"#)
        await model.vote(.five)
        XCTAssertEqual(model.release?.yourVote, 5)
        XCTAssertEqual(model.release?.grade, 4.66)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.actionError)
        for json in [#"{"id":72}"#, #"{"id":72,"your_vote":0}"#, #"{"id":72,"your_vote":99}"#] {
            let empty = ReleaseDetailViewModel(releaseID: 72, preloaded: try profileTestDecode(Release.self, json), session: rig.session)
            let requests = rig.api.requests.count
            await empty.removeVote()
            XCTAssertEqual(rig.api.requests.count, requests)
        }
    }

    @MainActor
    func testRandomReleaseFailureIsRetriableAndDoesNotRequestEpisodesOrPlayback() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let model = RandomReleaseViewModel(session: rig.session)
        rig.api.enqueue("/release/random", json: #"{"code":0}"#)
        await model.load()
        XCTAssertNil(model.release)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
        rig.api.enqueue("/release/random", json: #"{"code":0,"release":{"id":71,"title_ru":"Наруто"}}"#)
        await model.load()
        XCTAssertEqual(model.release?.id, 71)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(rig.api.requests.allSatisfy { $0.url?.path == "/release/random" })
        let request = try XCTUnwrap(rig.api.requests.first)
        XCTAssertNil(token(request))
        XCTAssertTrue(request.url?.query?.contains("extended_mode=true") == true)
    }

    @MainActor
    func testRandomReleaseSupersededViewerDoesNotAdoptLateRelease() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let held = rig.api.hold("/release/random")
        defer { held.respond("{}", status: 500) }
        let model = RandomReleaseViewModel(session: rig.session)
        let load = Task { await model.load() }
        defer { load.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        try await rig.signIn(token: "owner")
        held.respond(#"{"code":0,"release":{"id":71}}"#)
        await load.value
        XCTAssertFalse(model.hasCurrentViewer)
        XCTAssertNil(model.release)
        XCTAssertNil(model.errorMessage)
        let requests = rig.api.requests.count
        await model.load()
        XCTAssertEqual(rig.api.requests.count, requests)
    }

    @MainActor
    func testCancelledRandomReleaseCanRetryWithoutFalseFailure() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let held = rig.api.hold("/release/random")
        defer { held.respond("{}", status: 500) }
        let model = RandomReleaseViewModel(session: rig.session)
        let load = Task { await model.load() }
        defer { load.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        load.cancel()
        await load.value
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.release)
        rig.api.enqueue("/release/random", json: #"{"code":0,"release":{"id":71}}"#)
        await model.load()
        XCTAssertEqual(model.release?.id, 71)
    }
}
