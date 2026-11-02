import XCTest
@testable import AnixartKit

final class BrowsingContractTests: XCTestCase {
    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testReleaseSearchAndRelatedUseExplicitV2WithoutChangingOtherEndpoints() async throws {
        let client = AnixartClient(tokenStore: InMemoryTokenStore(token: "test-token", profileID: 42))
        let search = try await client.urlRequest(for: CatalogEndpoints.searchReleases("Naruto", page: 3, scope: .titleAlt))
        XCTAssertEqual(search.url?.path, "/search/releases/3")
        XCTAssertEqual(search.httpMethod, "POST")
        XCTAssertEqual(search.value(forHTTPHeaderField: "API-Version"), "v2")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(search.httpBody)) as? [String: Any])
        XCTAssertEqual(body["query"] as? String, "Naruto")
        XCTAssertEqual(body["searchBy"] as? Int, 3)
        XCTAssertNil(body["search_by"])
        let related = try await client.urlRequest(for: ReleaseEndpoints.related(relatedID: 17, page: 2))
        XCTAssertEqual(related.url?.path, "/related/17/2")
        XCTAssertEqual(related.value(forHTTPHeaderField: "API-Version"), "v2")
        let detail = try await client.urlRequest(for: ReleaseEndpoints.release(id: 71))
        XCTAssertEqual(detail.value(forHTTPHeaderField: "API-Version"), "2")
    }

    func testVideoCategoryUsesNumericIDAndNeitherVideoReadSendsAToken() async throws {
        let client = AnixartClient(tokenStore: InMemoryTokenStore(token: "test-token", profileID: 42))
        for endpoint in [ReleaseVideoEndpoints.videos(releaseID: 71, page: 1),
                         ReleaseVideoEndpoints.videos(releaseID: 71, categoryID: 9, page: 2)] {
            let request = try await client.urlRequest(for: endpoint)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.url?.query)
        }
        let category = try await client.urlRequest(for: ReleaseVideoEndpoints.videos(releaseID: 71, categoryID: 9, page: 2))
        XCTAssertEqual(category.url?.path, "/video/release/71/category/9/2")
    }

    func testOriginalDiscoverBannerActionsUseActionNotBannerID() throws {
        XCTAssertEqual(try decode(Interesting.self, #"{"id":999,"type":1,"action":"71"}"#).destination, .release(71))
        XCTAssertEqual(try decode(Interesting.self, #"{"id":999,"type":3,"action":"17"}"#).destination, .collection(17))
        XCTAssertEqual(try decode(Interesting.self, #"{"id":999,"type":2,"action":"https://example.invalid/info"}"#).destination,
                       .web(URL(string: "https://example.invalid/info")!))
        for json in [#"{"id":999,"type":99,"action":"71"}"#,
                     #"{"id":999,"type":1,"action":"-71"}"#,
                     #"{"id":999,"type":1,"action":"999999999999999999999999"}"#,
                     #"{"id":999,"type":3,"action":"not-an-id"}"#,
                     #"{"id":999,"type":1,"action":"71","isHidden":true}"#,
                     #"{"id":999,"action":"71"}"#] {
            XCTAssertNil(try decode(Interesting.self, json).destination, json)
        }
    }

    func testVideoBannerActionsDoNotGuessFromNameOrUnknownAction() throws {
        XCTAssertEqual(try decode(ReleaseVideoBanner.self, #"{"action_id":0,"value":"9","name":"Опенинги"}"#).destination, .category(9))
        XCTAssertEqual(try decode(ReleaseVideoBanner.self, #"{"action_id":1,"value":"https://example.invalid/watch"}"#).destination,
                       .web(URL(string: "https://example.invalid/watch")!))
        for json in [#"{"action_id":0,"name":"9"}"#,
                     #"{"action_id":0,"value":"0"}"#,
                     #"{"action_id":0,"value":"https://example.invalid/watch"}"#,
                     #"{"action_id":7,"value":"9"}"#,
                     #"{"value":"9"}"#] {
            XCTAssertNil(try decode(ReleaseVideoBanner.self, json).destination, json)
        }
    }

    func testUnsafeOrRelativeURLsNeverOpenAndValidVideoFallbackSurvives() throws {
        for value in ["", "/relative", "javascript:alert(1)", "file:///private/test", "https://",
                      "https://user:password@example.invalid/watch", "https://example.invalid/a b"] {
            let data = try JSONSerialization.data(withJSONObject: ["id": 1, "player_url": value, "url": value])
            XCTAssertNil(try JSONDecoder().decode(ReleaseVideo.self, from: data).playbackURL, value)
            let bannerData = try JSONSerialization.data(withJSONObject: ["id": 1, "type": 2, "action": value])
            XCTAssertNil(try JSONDecoder().decode(Interesting.self, from: bannerData).destination, value)
        }
        let video = try decode(ReleaseVideo.self, #"{"id":1,"player_url":"","url":"https://example.invalid/watch"}"#)
        XCTAssertEqual(video.playbackURL?.absoluteString, "https://example.invalid/watch")
        let preferred = try decode(ReleaseVideo.self, #"{"id":1,"player_url":"https://example.invalid/player","url":"https://example.invalid/watch"}"#)
        XCTAssertEqual(preferred.playbackURL?.path, "/player")
    }

    func testFranchiseSearchResponseCarriesItsOwnHeaderAndArtwork() throws {
        let response = try decode(ReleaseSearchResponse.self,
            #"{"code":0,"related":{"id":17,"name_ru":"Наруто","description":"Произведение","release_count":27,"images":["https://example.invalid/1.jpg","https://example.invalid/2.jpg","https://example.invalid/1.jpg"]},"releases":[]}"#)
        let related = try XCTUnwrap(response.related)
        XCTAssertEqual(related.id, 17)
        XCTAssertEqual(related.displayName, "Наруто")
        XCTAssertEqual(related.description, "Произведение")
        XCTAssertEqual(related.releaseCountText, "27 релизов во франшизе")
        XCTAssertEqual(related.posterURLs.count, 2)
        XCTAssertEqual(response.releases, [])
        XCTAssertNil(try decode(Related.self, #"{"id":17}"#).releaseCountText)
    }

    func testTitleCopyFieldsDoNotInventAbsentOrBlankTitles() throws {
        let release = try decode(Release.self, #"{"id":71,"title_ru":"Наруто","title_original":"Naruto","title_alt":"  \n  "}"#)
        XCTAssertEqual(release.titleFields.map(\.kind), [.russian, .original])
        XCTAssertEqual(release.titleFields.map(\.value), ["Наруто", "Naruto"])
        XCTAssertEqual(release.titleFields.map(\.label), ["Название", "Оригинальное название"])
        XCTAssertTrue(try decode(Release.self, #"{"id":71}"#).titleFields.isEmpty)
    }

    func testCompactAndDetailRatingPrecisionAndUnknownEpisodeCounts() throws {
        let release = try decode(Release.self, #"{"id":71,"grade":4.66,"episodes_released":4}"#)
        XCTAssertEqual(release.ratingText, "4.7")
        XCTAssertEqual(release.ratingDetailText, "4.66")
        XCTAssertEqual(release.episodeProgressText, "4 из ? эп")
        XCTAssertNil(try decode(Release.self, #"{"id":71}"#).episodeProgressText)
        XCTAssertEqual(try decode(Release.self, #"{"id":71,"episodes_total":1}"#).episodeProgressText, "? из 1 эп")
    }

    func testDailyDiscussionDoesNotFallBackToLifetimeCommentCount() throws {
        let release = try decode(Release.self, #"{"id":71,"comment_per_day_count":134,"comment_count":9999}"#)
        XCTAssertEqual(release.commentCount, 9999)
        XCTAssertEqual(release.dailyDiscussionText, "134 комментария")
        XCTAssertNil(try decode(Release.self, #"{"id":71,"comment_count":9999}"#).dailyDiscussionText)
    }

    func testEmptyFilterSelectionsNormalizeToOmittedKeysWithoutChangingSort() throws {
        var request = FilterRequest(sort: .yearAscending, country: "  \n ", studio: " OLM ", genres: [], genresMode: .exclude,
                                    types: [], ageRatings: [], profileListExclusions: [])
        request.source = " "
        let normalized = request.normalized
        XCTAssertEqual(normalized.sort, 6)
        XCTAssertEqual(normalized.studio, "OLM")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(normalized)) as? [String: Any])
        for key in ["country", "source", "genres", "genres_mode", "is_genres_exclude_mode_enabled", "types", "age_ratings", "profile_list_exclusions"] {
            XCTAssertNil(json[key], key)
        }
        XCTAssertEqual(request.country, "  \n ", "Normalization does not mutate the editor's value")
    }

    func testFullFilterBadgeIncludesPreviouslyMissingConstraintGroups() {
        var request = FilterRequest(episodeDuration: .upTo10, country: "Япония", studio: "OLM", source: .manga)
        XCTAssertEqual(request.activeConstraintCount, 4)
        request.episodesTo = 12
        XCTAssertEqual(request.activeConstraintCount, 5)
        request.profileListExclusions = [1, 3]
        XCTAssertEqual(request.activeConstraintCount, 6)
        XCTAssertNil(request.withoutProfileListExclusions.profileListExclusions)
        XCTAssertEqual(request.profileListExclusions, [1, 3])
        XCTAssertEqual(FilterRequest(sort: .gradeDescending).activeConstraintCount, 0)
    }

    func testYearRangeValidationAllowsAnnouncementsButRejectsContradictions() {
        XCTAssertNotNil(FilterRequest(startYear: 2026, endYear: 2002).validationMessage)
        XCTAssertNotNil(FilterRequest(startYear: 0).validationMessage)
        XCTAssertNil(FilterRequest(startYear: 2030, endYear: 2031).validationMessage)
        XCTAssertNil(FilterRequest(startYear: 2002, endYear: 2002).validationMessage)
    }

    func testFullFilterStudioSourceDurationAndSortUseAPKValuesAndKeys() async throws {
        XCTAssertEqual(CatalogSort.displayOrder.map(\.rawValue), [0, 4, 1, 5, 2, 6, 3, 7])
        let client = AnixartClient(tokenStore: InMemoryTokenStore())
        let filter = FilterRequest(sort: .popularAscending, episodeDuration: .upTo30, country: "Япония",
                                   studio: "OLM", source: .manga, types: [9], ageRatings: [0, 4])
        let request = try await client.urlRequest(for: CatalogEndpoints.filter(filter, page: 2))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(json["sort"] as? Int, 7)
        XCTAssertEqual(json["country"] as? String, "Япония")
        XCTAssertEqual(json["studio"] as? String, "OLM")
        XCTAssertEqual(json["source"] as? String, "Манга")
        XCTAssertEqual(json["episode_duration_from"] as? Int, 11)
        XCTAssertEqual(json["episode_duration_to"] as? Int, 30)
        XCTAssertEqual(json["types"] as? [Int], [9])
        XCTAssertEqual(json["age_ratings"] as? [Int], [0, 4])
        XCTAssertNil(json["episodeDurationFrom"])
        XCTAssertNil(json["source_id"])
    }

    func testOnlyRealFiveStarVotesAreDisplayedAsCurrent() throws {
        for value in [-1, 0, 6, 99] {
            XCTAssertNil(try decode(Release.self, "{\"id\":71,\"your_vote\":\(value)}").validatedYourVote)
        }
        XCTAssertEqual(try decode(Release.self, #"{"id":71,"your_vote":5}"#).validatedYourVote, 5)
        XCTAssertNil(try decode(Release.self, #"{"id":71}"#).validatedYourVote)
    }
}
