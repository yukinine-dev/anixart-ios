import Foundation
import XCTest
@testable import AnixartKit

final class ProfileStatisticsPreferencesTests: XCTestCase {
    private func profile(_ fields: String = "") throws -> Profile {
        try JSONDecoder().decode(Profile.self, from: Data("{\"id\":42\(fields)}".utf8))
    }

    func testMissingNullAndEmptyGroupsDoNotCreatePlaceholderRows() throws {
        for fields in ["", #", "preferred_genres":null,"preferred_audiences":null,"preferred_themes":null"#,
                       #", "preferred_genres":[],"preferred_audiences":[],"preferred_themes":[]"#] {
            XCTAssertTrue(ProfileStatisticsPreferences(profile: try profile(fields)).rows.isEmpty)
        }
    }

    func testUnnamedAndWhitespaceOnlyEntriesDoNotCountAsPreferenceData() throws {
        let value = try profile(#", "preferred_genres":[{}, {"name":""}, {"name":" \n\t ","percentage":20}],"preferred_audiences":[{"percentage":7}]"#)
        XCTAssertTrue(ProfileStatisticsPreferences(profile: value).rows.isEmpty)
    }

    func testEachPreferenceGroupHasIndependentAvailability() throws {
        let value = try profile(#", "preferred_genres":[],"preferred_audiences":[{"name":"сёнен","percentage":7}],"preferred_themes":null"#)
        let rows = ProfileStatisticsPreferences(profile: value).rows
        XCTAssertEqual(rows.map(\.title), ["Аудитория:"])
        XCTAssertEqual(rows.map(\.value), ["сёнен 7%"])
    }

    func testFilledPreferencesRetainServerOrderAndOriginalPercentagePresentation() throws {
        let value = try profile(#" ,"preferred_genres":[{"name":"экшен","percentage":11},{"name":"фэнтези","percentage":10},{"name":"романтика","percentage":8}],"preferred_audiences":[{"name":"сёнен","percentage":6}],"preferred_themes":[{"name":"школа","percentage":7}]"#)
        let rows = ProfileStatisticsPreferences(profile: value).rows
        XCTAssertEqual(rows.map(\.title), ["Жанры:", "Аудитория:", "Тематика:"])
        XCTAssertEqual(rows.map(\.value), ["экшен 11%, фэнтези 10%, романтика 8%", "сёнен 6%", "школа 7%"])
        XCTAssertEqual(Set(rows.map(\.id)).count, 3)
    }

    func testSparseOrInvalidPercentagesKeepNamesWithoutInventingAPercentage() throws {
        let value = try profile(#", "preferred_genres":[{"name":" экшен \n"},{"name":"комедия","percentage":-1},{"name":"драма","percentage":101}]"#)
        XCTAssertEqual(ProfileStatisticsPreferences(profile: value).rows.first?.value, "экшен, комедия, драма")
    }

    func testRoundedZeroAndFullPercentagesRemainValidServerData() throws {
        let value = try profile(#", "preferred_genres":[{"name":"драма","percentage":0},{"name":"экшен","percentage":100}]"#)
        XCTAssertEqual(ProfileStatisticsPreferences(profile: value).rows.first?.value, "драма 0%, экшен 100%")
    }

    func testDailyServerPreferencesAreNotInferredFromCurrentCompletedCount() throws {
        for count in [0, 8, 10, 755] {
            let empty = try profile(",\"completed_count\":\(count)")
            XCTAssertTrue(ProfileStatisticsPreferences(profile: empty).rows.isEmpty)
            var supplied = empty
            supplied.preferredGenres = try JSONDecoder().decode([ProfileGenre].self, from: Data(#"[{"name":"экшен","percentage":11}]"#.utf8))
            XCTAssertEqual(ProfileStatisticsPreferences(profile: supplied).rows.first?.value, "экшен 11%")
        }
    }

    func testHiddenStatisticsNeverExposeSuppliedPreferenceRowsOrChangeTheWireModel() throws {
        let value = try profile(#", "is_stats_hidden":true,"preferred_genres":[{"name":"экшен","percentage":11}]"#)
        let before = try JSONEncoder().encode(value)
        XCTAssertTrue(ProfileStatisticsPreferences(profile: value).rows.isEmpty)
        XCTAssertFalse(value.visibleSections.contains(.statistics))
        XCTAssertEqual(try JSONDecoder().decode(Profile.self, from: before), value)
        XCTAssertEqual(value.preferredGenres?.first?.name, "экшен")
    }
}
