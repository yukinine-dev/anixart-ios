import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class SearchBookmarksPresentationTests: XCTestCase {
    @MainActor
    func testBookmarksAreTheThirdRootTab() {
        XCTAssertEqual(RootView.Tab.allCases, [.home, .discover, .bookmarks, .feed, .profile])
        XCTAssertEqual(RootView.Tab.allCases[2].title, "Закладки")
        XCTAssertEqual(RootView.Tab.allCases.map(\.title), ["Главная", "Обзор", "Закладки", "Лента", "Профиль"])
    }

    @MainActor
    func testBookmarksDefaultToFavoritesWithoutOverwritingAnExplicitPreference() {
        typealias Tab = BookmarksView.BookmarkTab
        XCTAssertEqual(Tab.defaultSelection(storageKey: nil), .favorites)
        XCTAssertEqual(Tab.defaultSelection(storageKey: ""), .favorites)
        XCTAssertEqual(Tab.defaultSelection(storageKey: "unknown"), .favorites)
        XCTAssertEqual(Tab.defaultSelection(storageKey: "list.1"), .list(.watching))
        XCTAssertEqual(Tab.allCases.map(\.title), ["Коллекции", "История", "Избранное", "Смотрю", "В планах", "Просмотрено", "Отложено", "Брошено"])
        for tab in Tab.allCases { XCTAssertEqual(Tab.defaultSelection(storageKey: tab.storageKey), tab) }
    }

    @MainActor
    func testFullFilterDraftExportsEveryVisibleConstraintWithTheCorrectWireValues() throws {
        let draft = CatalogFilterDraft(FilterRequest())
        draft.request.country = "Япония"
        draft.category = .series
        draft.genres = ["драма", "комедия"]
        draft.genreMode = .all
        draft.excludedLists = [.completed, .dropped]
        draft.typeIDs = [9, 17]
        draft.request.studio = "OLM"
        draft.source = .manga
        draft.request.startYear = 2002
        draft.request.endYear = 2026
        draft.season = .autumn
        draft.episodes = .from13to25
        draft.status = .released
        draft.episodeDuration = .upTo30
        draft.ageRatings = [0, 4]
        draft.sort = .gradeDescending
        XCTAssertNil(draft.validationMessage)
        XCTAssertEqual(draft.filter.activeConstraintCount, 13)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft.filter)) as? [String: Any])
        XCTAssertEqual(json["country"] as? String, "Япония")
        XCTAssertEqual(json["category_id"] as? Int, 1)
        XCTAssertEqual(json["genres"] as? [String], ["драма", "комедия"])
        XCTAssertEqual(json["genres_mode"] as? Int, 0)
        XCTAssertEqual(json["profile_list_exclusions"] as? [Int], [3, 5])
        XCTAssertEqual(json["types"] as? [Int], [9, 17])
        XCTAssertEqual(json["studio"] as? String, "OLM")
        XCTAssertEqual(json["source"] as? String, "Манга")
        XCTAssertEqual(json["start_year"] as? Int, 2002)
        XCTAssertEqual(json["end_year"] as? Int, 2026)
        XCTAssertEqual(json["season"] as? Int, 4)
        XCTAssertEqual(json["episodes_from"] as? Int, 13)
        XCTAssertEqual(json["episodes_to"] as? Int, 25)
        XCTAssertEqual(json["status_id"] as? Int, 1)
        XCTAssertEqual(json["episode_duration_from"] as? Int, 11)
        XCTAssertEqual(json["episode_duration_to"] as? Int, 30)
        XCTAssertEqual(json["age_ratings"] as? [Int], [0, 4])
        XCTAssertEqual(json["sort"] as? Int, 1)
        XCTAssertNil(json["query"])
        XCTAssertNil(json["searchBy"])
    }

    @MainActor
    func testEpisodePresetsRoundTripAsRangesAndCanBeCleared() {
        let draft = CatalogFilterDraft(FilterRequest())
        for preset in EpisodeCountPreset.allCases {
            draft.episodes = preset
            XCTAssertEqual(draft.episodes, preset)
            XCTAssertEqual(draft.filter.episodesFrom, preset.range.from)
            XCTAssertEqual(draft.filter.episodesTo, preset.range.to)
        }
        for preset in EpisodeDurationPreset.allCases {
            draft.episodeDuration = preset
            XCTAssertEqual(draft.episodeDuration, preset)
            XCTAssertEqual(draft.filter.episodeDurationFrom, preset.range.from)
            XCTAssertEqual(draft.filter.episodeDurationTo, preset.range.to)
        }
        draft.episodes = nil
        draft.episodeDuration = nil
        XCTAssertNil(draft.filter.episodesFrom)
        XCTAssertNil(draft.filter.episodesTo)
        XCTAssertNil(draft.filter.episodeDurationFrom)
        XCTAssertNil(draft.filter.episodeDurationTo)
    }

    @MainActor
    func testGenreModeChangesClearTheOldExclusionFlagAndLastGenreClearsBothKeys() {
        let draft = CatalogFilterDraft(FilterRequest())
        XCTAssertEqual(draft.genreMode, .any)
        draft.genres = ["драма"]
        XCTAssertEqual(draft.filter.genresMode, 1)
        draft.genreMode = .exclude
        XCTAssertEqual(draft.filter.genresMode, 2)
        XCTAssertEqual(draft.filter.isGenresExcludeModeEnabled, true)
        draft.genreMode = .all
        XCTAssertEqual(draft.filter.genresMode, 0)
        XCTAssertNil(draft.filter.isGenresExcludeModeEnabled)
        draft.genres = []
        XCTAssertNil(draft.filter.genres)
        XCTAssertNil(draft.filter.genresMode)
        XCTAssertNil(draft.filter.isGenresExcludeModeEnabled)
        draft.genreMode = .exclude
        XCTAssertEqual(draft.filter.activeConstraintCount, 0)
        XCTAssertNil(draft.filter.genresMode, "Choosing a mode without genres must not add an invisible constraint")
    }

    @MainActor
    func testYearSummaryValidationResetAndDraftIsolation() {
        let original = FilterRequest(startYear: 2002, endYear: 2002, country: "Япония")
        let draft = CatalogFilterDraft(original)
        XCTAssertEqual(draft.yearsSummary, "2002")
        draft.request.endYear = 2026
        XCTAssertEqual(draft.yearsSummary, "2002–2026")
        draft.request.startYear = nil
        XCTAssertEqual(draft.yearsSummary, "до 2026")
        draft.request.startYear = 2030
        draft.request.endYear = nil
        XCTAssertEqual(draft.yearsSummary, "с 2030")
        XCTAssertNil(draft.validationMessage, "Announcements can use future years")
        draft.request.endYear = 2002
        XCTAssertNotNil(draft.validationMessage)
        XCTAssertEqual(original.startYear, 2002)
        XCTAssertEqual(original.endYear, 2002, "Editing/cancelling a draft never mutates its source filter")
        draft.reset()
        XCTAssertEqual(draft.filter, FilterRequest())
        XCTAssertNil(draft.yearsSummary)
        XCTAssertNil(draft.validationMessage)
        XCTAssertEqual(draft.genreMode, .any)
    }

    func testRecentHistoryShowsEpisodeAndAbsoluteLocalDateAndTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        calendar.timeZone = utc
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 14, minute: 5)))
        let timestamp = Int(date.timeIntervalSince1970)
        let release = try profileTestDecode(Release.self, "{\"id\":71,\"last_view_episode\":{\"position\":7},\"last_view_timestamp\":\(timestamp)}")
        let subtitle = try XCTUnwrap(ReleaseHistoryMetadata.subtitle(release, timeZone: utc))
        XCTAssertEqual(subtitle, "7 серия • 1 окт. 2026 в 14:05")
        let moscow = try XCTUnwrap(TimeZone(secondsFromGMT: 3 * 3600))
        XCTAssertEqual(ReleaseHistoryMetadata.subtitle(release, timeZone: moscow), "7 серия • 1 окт. 2026 в 17:05")
        XCTAssertFalse(subtitle.contains("назад"))
        XCTAssertFalse(subtitle.contains("сегодня"))
    }

    func testSparseHistoryDoesNotRenderEmptySeparatorsOrInventAnEpisode() throws {
        let episodeOnly = try profileTestDecode(Release.self, #"{"id":71,"last_view_episode":{"name":"OVA"}}"#)
        XCTAssertEqual(ReleaseHistoryMetadata.subtitle(episodeOnly), "OVA")
        let dateOnly = try profileTestDecode(Release.self, #"{"id":71,"last_view_timestamp":1790863500}"#)
        let subtitle = try XCTUnwrap(ReleaseHistoryMetadata.subtitle(dateOnly, timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0))))
        XCTAssertTrue(subtitle.contains("2026"))
        XCTAssertFalse(subtitle.contains("•"))
        XCTAssertFalse(subtitle.contains("серия"))
        XCTAssertNil(ReleaseHistoryMetadata.subtitle(try profileTestDecode(Release.self, #"{"id":71}"#)))
        XCTAssertNil(Format.dateTime(nil))
    }
}
