import XCTest
@testable import AnixartKit

/// Anixart puts the session token in the query string and routes reads through POST
/// bodies, so these assert the wire shape of a request without touching the network.
final class EndpointTests: XCTestCase {
    private func client(token: String?) -> AnixartClient {
        AnixartClient(tokenStore: InMemoryTokenStore(token: token, profileID: token == nil ? nil : 42))
    }

    func testTokenTravelsAsAQueryParameter() async throws {
        let request = try await client(token: "abc123")
            .urlRequest(for: ReleaseEndpoints.release(id: 9243))
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.host, "api-s.anixsekai.com")
        XCTAssertEqual(components.path, "/release/9243")
        XCTAssertEqual(components.queryItems?.first { $0.name == "token" }?.value, "abc123")
        XCTAssertEqual(components.queryItems?.first { $0.name == "extended_mode" }?.value, "true")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "API-Version"), "2")
    }

    func testGuestRequestOmitsTokenEntirely() async throws {
        let request = try await client(token: nil)
            .urlRequest(for: ReleaseEndpoints.release(id: 1))
        let query = try XCTUnwrap(request.url?.query)
        XCTAssertFalse(query.contains("token="))
    }

    func testAuthRequiredEndpointFailsWithoutAToken() async {
        do {
            _ = try await client(token: nil)
                .urlRequest(for: BookmarkEndpoints.favorites(page: 0))
            XCTFail("expected .notAuthenticated")
        } catch let error as AnixartError {
            guard case .notAuthenticated(let path) = error else {
                return XCTFail("expected .notAuthenticated, got \(error)")
            }
            XCTAssertEqual(path, "favorite/all/0")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testUnauthenticatedEndpointNeverSendsAToken() async throws {
        // `episode/{releaseId}/{typeId}` takes no token in the Android client.
        let request = try await client(token: "abc123")
            .urlRequest(for: EpisodeEndpoints.sources(releaseID: 9243, typeID: 4))
        XCTAssertEqual(request.url?.path, "/episode/9243/4")
        XCTAssertNil(request.url?.query)
    }

    func testCatalogueFilterIsAPostWithAJSONBody() async throws {
        let filter = FilterRequest(
            sort: .gradeDescending,
            categoryId: 1,
            season: .winter,
            startYear: 2015,
            genres: ["Драма"],
            genresMode: .exclude,
            profileListExclusions: [.completed, .dropped]
        )
        let request = try await client(token: "t")
            .urlRequest(for: CatalogEndpoints.filter(filter, page: 0))

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/filter/0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(json["sort"] as? Int, 1)
        XCTAssertEqual(json["category_id"] as? Int, 1)
        XCTAssertEqual(json["season"] as? Int, 1)
        XCTAssertEqual(json["start_year"] as? Int, 2015)
        XCTAssertEqual(json["genres"] as? [String], ["Драма"])
        XCTAssertEqual(json["genres_mode"] as? Int, 2)
        XCTAssertEqual(json["is_genres_exclude_mode_enabled"] as? Bool, true)
        XCTAssertEqual(json["profile_list_exclusions"] as? [Int], [3, 5])
        // Unset constraints must be absent, not null.
        XCTAssertNil(json["status_id"])
        XCTAssertNil(json["end_year"])
        XCTAssertNil(json["studio"])
    }

    func testSearchBodyKeepsTheApisCamelCaseField() async throws {
        let request = try await client(token: "t")
            .urlRequest(for: CatalogEndpoints.searchReleases("стальной", page: 2, scope: .titleRu))
        XCTAssertEqual(request.url?.path, "/search/releases/2")

        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any]
        )
        XCTAssertEqual(json["query"] as? String, "стальной")
        XCTAssertEqual(json["searchBy"] as? Int, 1)
    }

    func testAuthEndpointsAreFormEncoded() async throws {
        let request = try await client(token: nil)
            .urlRequest(for: AuthEndpoints.signIn(login: "user name", password: "p@ss&word"))

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/x-www-form-urlencoded; charset=utf-8"
        )
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)
        // Space becomes '+' and reserved characters are escaped, as OkHttp's FormBody does.
        XCTAssertEqual(body, "login=user+name&password=p%40ss%26word")
    }

    func testSignUpAsksForTheLongCode() async throws {
        let request = try await client(token: nil)
            .urlRequest(for: AuthEndpoints.signUp(login: "a", email: "a@b.c", password: "x"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Long-Code"), "1")
    }

    func testBookmarkSortAndAnnounceFilter() async throws {
        let withFilter = try await client(token: "t").urlRequest(
            for: BookmarkEndpoints.list(.watching, page: 3, sort: .ratingDescending, hideAnnounces: true)
        )
        let components = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(withFilter.url), resolvingAgainstBaseURL: false)
        )
        XCTAssertEqual(components.path, "/profile/list/all/1/3")
        XCTAssertEqual(components.queryItems?.first { $0.name == "sort" }?.value, "7")
        XCTAssertEqual(components.queryItems?.first { $0.name == "filter_announce" }?.value, "1")

        // Absent rather than `0`, matching Retrofit dropping a null @Query.
        let withoutFilter = try await client(token: "t")
            .urlRequest(for: BookmarkEndpoints.list(.watching, page: 0))
        XCTAssertFalse(try XCTUnwrap(withoutFilter.url?.query).contains("filter_announce"))
    }

    func testMirrorHostRewriting() {
        XCTAssertEqual(
            AnixartURL.mirrored(URL(string: "https://static.anixart.tv/posters/1.jpg")!).absoluteString,
            "https://mirror-static.anixart.tv/posters/1.jpg"
        )
        XCTAssertEqual(
            AnixartURL.mirrored(URL(string: "https://anixart.tv/x")!).absoluteString,
            "https://mirror.anixart.tv/x"
        )
    }

    func testClientAdoptsHostsFromConfigUrls() async throws {
        let client = self.client(token: "t")
        var config = ConfigUrlsResponse()
        config.apiUrls = ["https://api-2.anixsekai.com"]
        config.shouldUseMirrorUrls = false
        await client.apply(config)

        let request = try await client.urlRequest(for: ReleaseEndpoints.release(id: 5))
        XCTAssertEqual(request.url?.host, "api-2.anixsekai.com")
        // A host advertised without a trailing slash must not swallow the path.
        XCTAssertEqual(request.url?.path, "/release/5")
    }

    func testEpisodeProgressIsAWriteUnderHistory() async throws {
        let request = try await client(token: "t")
            .urlRequest(for: EpisodeEndpoints.markWatched(releaseID: 1, sourceID: 2, position: 3))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/episode/watch/1/2/3")
    }
}
