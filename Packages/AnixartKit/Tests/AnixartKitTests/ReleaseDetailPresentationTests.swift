import Foundation
import XCTest
@testable import AnixartKit

final class ReleaseDetailPresentationTests: XCTestCase {
    func testWholeVisibleFranchiseDoesNotOfferAnEmptyMoreRoute() throws {
        for count in 0...3 {
            let release = try decode([
                "related": ["id": 8, "release_count": count],
                "related_count": count,
                "related_releases": (0..<count).map { ["id": $0 + 1] }
            ])
            XCTAssertEqual(release.relatedPreviewReleases.count, count)
            XCTAssertFalse(release.hasMoreRelatedReleases)
        }
    }

    func testMoreRouteOnlyAppearsForHiddenTitlesAndUsesUniquePreviewIDs() throws {
        let release = try decode([
            "related": ["id": 8, "release_count": 4],
            "related_releases": [1, 1, 2, 3, 4].map { ["id": $0] }
        ])
        XCTAssertEqual(release.relatedPreviewReleases.map(\.id), [1, 2, 3])
        XCTAssertTrue(release.hasMoreRelatedReleases)

        let duplicates = try decode([
            "related": ["id": 8, "release_count": 2],
            "related_releases": [1, 1, 2].map { ["id": $0] }
        ])
        XCTAssertEqual(duplicates.relatedPreviewReleases.map(\.id), [1, 2])
        XCTAssertFalse(duplicates.hasMoreRelatedReleases)
    }

    func testSparseAndPartiallyLoadedFranchisesRemainReachable() throws {
        XCTAssertTrue(try decode(["related": ["id": 8]]).hasMoreRelatedReleases)
        XCTAssertTrue(try decode([
            "related": ["id": 8], "related_count": 5,
            "related_releases": [["id": 1], ["id": 2]]
        ]).hasMoreRelatedReleases)
        XCTAssertFalse(try decode(["related_releases": [["id": 1]]]).hasMoreRelatedReleases)
    }

    func testCountryFlagPreservesTheReadableCountryAndSeason() throws {
        for (country, flag) in [("Япония", "🇯🇵"), ("  Китай \n", "🇨🇳"), ("Южная Корея", "🇰🇷"), ("JP", "🇯🇵")] {
            XCTAssertEqual(try decode(["country": country]).countryFlag, flag)
        }
        let release = try decode(["country": "Япония", "season": 4, "year": "2026"])
        XCTAssertEqual(release.countryAndSeasonLine, "Япония, осень 2026 г.")
        for country in ["", " ", "Неизвестно", "Япония, Китай"] {
            XCTAssertNil(try decode(["country": country]).countryFlag)
        }
    }

    func testBadgesPreferServerLabelsAndNeverInventAnUnknownType() throws {
        let release = try decode([
            "status": ["id": 1, "name": " Завершён "], "status_id": 1,
            "category": ["id": 1, "name": " Сериал "]
        ])
        XCTAssertEqual(release.statusBadgeText, "Завершён")
        XCTAssertEqual(release.categoryBadgeText, "Сериал")
        XCTAssertEqual(try decode(["status_id": 2]).statusBadgeText, "Выходит")
        XCTAssertNil(try decode(["status_id": 999]).statusBadgeText)
        XCTAssertNil(try decode(["category": ["id": 999, "name": " \n "]]).categoryBadgeText)
    }

    func testShareAndCopyUseTheSameReleaseWebRoute() throws {
        let release = try decode([:])
        XCTAssertEqual(release.shareURL.absoluteString, "https://anixart-app.com/release/71")
        XCTAssertNil(release.shareURL.query)
        XCTAssertNil(release.shareURL.fragment)
    }

    func testReleaseReportReusesTheExistingAuthenticatedReportContract() async throws {
        let client = AnixartClient(tokenStore: InMemoryTokenStore(token: "fixture-token", profileID: 42))
        let reasons = try await client.urlRequest(for: ReportEndpoints.reasons(for: .release))
        XCTAssertEqual(reasons.url?.path, "/report/release/reasons")
        XCTAssertEqual(reasons.httpMethod, "GET")
        let report = try await client.urlRequest(for: ReportEndpoints.send(to: .release, request: .init(
            entityID: 71, reasonID: 777, message: "Текст жалобы"
        )))
        XCTAssertEqual(report.url?.path, "/report/release")
        XCTAssertEqual(report.httpMethod, "POST")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(report.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["entity_id", "reason", "message"])
        XCTAssertEqual(body["entity_id"] as? Int, 71)
        XCTAssertEqual(body["reason"] as? Int, 777)
        XCTAssertTrue(report.url?.query?.contains("token=fixture-token") == true)
    }

    private func decode(_ fields: [String: Any]) throws -> Release {
        var fields = fields
        fields["id"] = 71
        return try JSONDecoder().decode(Release.self, from: JSONSerialization.data(withJSONObject: fields))
    }
}
