import XCTest
@testable import AnixartKit

final class ReleaseSourceMaterialContractTests: XCTestCase {
    func testSourceLinkUsesOriginalSearchByFiveNotFilterOrExternalURL() async throws {
        let client = AnixartClient(tokenStore: InMemoryTokenStore())
        let request = try await client.urlRequest(for: CatalogEndpoints.searchReleases("Манга", page: 2, scope: .sourceMaterial))
        XCTAssertEqual(request.url?.path, "/search/releases/2")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "API-Version"), "v2")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["query"] as? String, "Манга")
        XCTAssertEqual(body["searchBy"] as? Int, 5)
        XCTAssertNil(body["source"])
        XCTAssertNil(body["genres"])
        XCTAssertNil(body["source_id"])
    }

    func testSourceRouteUsesActualSourceFieldAndPreservesTitleMenu() throws {
        let release = try JSONDecoder().decode(Release.self, from: Data(#"{"id":71,"source":"Манга","title_ru":"Наруто","studio":"Studio"}"#.utf8))
        XCTAssertEqual(release.sourceMaterialSearch, .manga)
        XCTAssertEqual(release.sourceMaterialSearch?.rawValue, "Манга")
        XCTAssertEqual(SearchScope.sourceMaterial.rawValue, 5)
        XCTAssertEqual(SearchScope.titleSearchScopes.map(\.rawValue), [0, 1, 2, 3])
        XCTAssertFalse(SearchScope.titleSearchScopes.contains(.sourceMaterial))
    }

    func testUnknownOrInvalidSourceValuesDoNotInventDestinations() throws {
        for source in ["", " \n ", "Unknown", "javascript:alert(1)", "https://example.invalid/info", "Манга#other", "<a>Манга</a>"] {
            let data = try JSONSerialization.data(withJSONObject: ["id": 71, "source": source])
            XCTAssertNil(try JSONDecoder().decode(Release.self, from: data).sourceMaterialSearch, source)
        }
        for source in SourceMaterial.allCases {
            let data = try JSONSerialization.data(withJSONObject: ["id": 71, "source": source.rawValue])
            XCTAssertEqual(try JSONDecoder().decode(Release.self, from: data).sourceMaterialSearch, source)
        }
    }
}
