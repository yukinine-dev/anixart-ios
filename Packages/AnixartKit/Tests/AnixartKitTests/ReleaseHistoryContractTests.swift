import Foundation
import XCTest
@testable import AnixartKit

final class ReleaseHistoryContractTests: XCTestCase {
    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testProfileHistoryUsesEmbeddedEpisodeWhenFlatLabelIsAbsent() throws {
        let profile = try decode(Profile.self, #"""
        {"id":42,"history":[{"id":71,"last_view_timestamp":1790863500,
         "last_view_episode":{"name":"7 серия","position":7},"last_view_episode_type_name":"AniLibria"}]}
        """#)
        let release = try XCTUnwrap(profile.history?.first)
        XCTAssertNil(release.lastViewEpisodeName)
        XCTAssertEqual(release.lastViewedEpisodeText, "7 серия")
        XCTAssertEqual(release.continueWatchingText, "7 серия · AniLibria")
        XCTAssertEqual(release.lastViewedDate?.timeIntervalSince1970, 1_790_863_500)
    }

    func testFlatHistoryLabelIsTrimmedAndPreserved() throws {
        let release = try decode(Release.self, #"""
        {"id":71,"last_view_episode_name":"  Серия 12  ","last_view_episode_type_name":"  AniLibria.TV \n",
         "last_view_episode":{"name":"Другое имя","position":12}}
        """#)
        XCTAssertEqual(release.lastViewedEpisodeText, "Серия 12")
        XCTAssertEqual(release.continueWatchingText, "Серия 12 · AniLibria.TV")
    }

    func testMissingEpisodeNamesFallBackOnlyToARealPositivePosition() throws {
        let release = try decode(Release.self, #"""
        {"id":71,"episodes_total":100,"last_view_episode_name":" \n ",
         "last_view_episode":{"name":" ","position":8}}
        """#)
        XCTAssertEqual(release.lastViewedEpisodeText, "8 серия")
        for json in [#"{"id":71,"episodes_total":100,"is_viewed":true}"#,
                     #"{"id":71,"last_view_episode":{"position":0}}"#,
                     #"{"id":71,"last_view_episode":{"position":-1}}"#,
                     #"{"id":71,"last_view_episode_name":" ","last_view_episode":null}"#] {
            let unknown = try decode(Release.self, json)
            XCTAssertNil(unknown.lastViewedEpisodeText, json)
            XCTAssertNil(unknown.continueWatchingText, json)
        }
    }

    func testAbsentHistoryTimestampsDoNotBecomeTheUnixEpoch() throws {
        for json in [#"{"id":71}"#, #"{"id":71,"last_view_timestamp":null}"#,
                     #"{"id":71,"last_view_timestamp":0}"#, #"{"id":71,"last_view_timestamp":-1}"#] {
            XCTAssertNil(try decode(Release.self, json).lastViewedDate, json)
        }
    }

    func testFranchiseBannerIsNotUsedAsAPosterInTheSearchStack() throws {
        let related = try decode(Related.self, #"""
        {"id":17,"image":"https://example.invalid/banner.jpg",
         "images":["https://example.invalid/centre.jpg","https://example.invalid/right.jpg","https://example.invalid/left.jpg"]}
        """#)
        XCTAssertEqual(related.bannerURL?.lastPathComponent, "banner.jpg")
        XCTAssertEqual(related.posterURLs.map(\.lastPathComponent), ["centre.jpg", "right.jpg", "left.jpg"])
        let bannerOnly = try decode(Related.self, #"{"id":17,"image":"https://example.invalid/banner.jpg"}"#)
        XCTAssertTrue(bannerOnly.posterURLs.isEmpty)
        XCTAssertNotNil(bannerOnly.bannerURL)
    }

    func testGenreExclusionModeAndLegacyFlagNormalizeTogether() throws {
        for mode in GenresMode.allCases {
            let request = FilterRequest(genres: ["драма"], genresMode: mode).normalized
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
            XCTAssertEqual(json["genres_mode"] as? Int, mode.rawValue)
            XCTAssertEqual(json["is_genres_exclude_mode_enabled"] as? Bool, mode == .exclude ? true : nil)
        }
        var legacy = FilterRequest(genres: ["драма"], genresMode: .any)
        legacy.isGenresExcludeModeEnabled = true
        XCTAssertEqual(legacy.normalized.genresMode, GenresMode.exclude.rawValue)
        legacy.genres = []
        XCTAssertNil(legacy.normalized.genresMode)
        XCTAssertNil(legacy.normalized.isGenresExcludeModeEnabled)
    }
}
