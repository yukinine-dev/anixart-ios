import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class SourceMaterialSearchTests: XCTestCase {
    @MainActor
    func testStudioDirectorAndAuthorUseAPKReleaseSearchScopes() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        for (scope, query, wire) in [(SearchScope.studio, "Studio Bind", 1), (.director, "Манабу Окамото", 2), (.author, "Рифудзин на Магонотэ", 3)] {
            let view = SourceMaterialSearchView(query: query, scope: scope, title: query, viewer: rig.session.viewerKey)
            XCTAssertEqual(view.scope.rawValue, wire)
            rig.api.enqueue("/search/releases/0", json: #"{"code":0,"releases":[]}"#)
            let model = CatalogViewModel(session: rig.session, query: query, searchScope: scope)
            await model.search()
            let request = try XCTUnwrap(rig.api.requests.last)
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(body["searchBy"] as? Int, wire)
            XCTAssertEqual(body["query"] as? String, query)
            XCTAssertEqual(request.url?.path, "/search/releases/0")
        }
    }

    @MainActor
    func testSourceInitializerPreservesItsQueryScopeAndTitleAfterGeneralizingTheRoute() {
        let rig = ProfileTestRig()
        let view = SourceMaterialSearchView(source: .manga, viewer: rig.session.viewerKey)
        XCTAssertEqual(view.query, "Манга")
        XCTAssertEqual(view.scope, .sourceMaterial)
        XCTAssertEqual(view.title, "Манга")
    }

    @MainActor
    func testSourceRouteReadsScopedSearchWithoutReplacingHomeInputOrWritingAccount() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let home = CatalogViewModel(session: rig.session, filter: FilterRequest(studio: "OLM"), query: "Мой запрос", searchScope: .titleRu)
        let release = try profileTestDecode(Release.self, #"{"id":71,"source":"Манга"}"#)
        let source = try XCTUnwrap(release.sourceMaterialSearch)
        _ = SourceMaterialSearchView(source: source, viewer: rig.session.viewerKey)
        let model = CatalogViewModel(session: rig.session, query: source.rawValue, searchScope: .sourceMaterial)
        rig.api.enqueue("/search/releases/0", json: #"{"code":0,"releases":[{"id":72}]}"#)
        await model.search()
        let request = try XCTUnwrap(rig.api.requests.first)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["query"] as? String, "Манга")
        XCTAssertEqual(body["searchBy"] as? Int, 5)
        XCTAssertEqual(request.url?.path, "/search/releases/0")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(home.query, "Мой запрос")
        XCTAssertEqual(home.searchScope, .titleRu)
        XCTAssertEqual(home.filter.studio, "OLM")
        XCTAssertEqual(model.currentSearch?.items.map(\.id), [72])
        XCTAssertTrue(rig.api.requests.allSatisfy { $0.url?.path == "/search/releases/0" })
    }

    @MainActor
    func testSourceSearchKeepsSameScopeOnEveryRaw25Page() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let rows = (Array(1...24) + [24]).map { "{\"id\":\($0)}" }.joined(separator: ",")
        rig.api.enqueue("/search/releases/0", json: "{\"code\":0,\"releases\":[\(rows)]}")
        rig.api.enqueue("/search/releases/1", json: #"{"code":0,"releases":[{"id":24},{"id":25}]}"#)
        let model = ReleaseSearchModel(query: "Манга", scope: .sourceMaterial, session: rig.session)
        await model.loadFirstPageIfNeeded(debounce: false)
        XCTAssertTrue(model.hasMore)
        await model.loadNextPage()
        XCTAssertEqual(model.items.map(\.id), Array(1...25))
        XCTAssertFalse(model.hasMore)
        for request in rig.api.requests {
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(body["searchBy"] as? Int, 5)
            XCTAssertEqual(body["query"] as? String, "Манга")
            XCTAssertEqual(request.value(forHTTPHeaderField: "API-Version"), "v2")
        }
    }

    @MainActor
    func testOldSourceRouteCannotReadWithNewViewerOrAdoptLateResults() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let held = rig.api.hold("/search/releases/0")
        defer { held.respond("{}", status: 500) }
        let model = ReleaseSearchModel(query: "Манга", scope: .sourceMaterial, session: rig.session)
        let old = Task { await model.reload() }
        defer { old.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        try await rig.signIn()
        held.respond(#"{"code":0,"releases":[{"id":71}]}"#)
        await old.value
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNil(model.errorMessage)
        let count = rig.api.requests.count
        await model.reload()
        await model.retry()
        XCTAssertEqual(rig.api.requests.count, count)
    }
}
