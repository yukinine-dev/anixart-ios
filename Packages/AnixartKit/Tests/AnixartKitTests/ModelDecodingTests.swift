import XCTest
@testable import AnixartKit

/// These lock in the JSON key mapping taken from the APK. The API mixes snake_case
/// and camelCase (`is_watched` next to `playbackPosition`), so a wrong key here is
/// a silently nil field at runtime rather than a decode error.
final class ModelDecodingTests: XCTestCase {
    func testDecodesRelease() throws {
        let response = try Fixture.decode(ReleaseResponse.self, from: "release")
        let release = try XCTUnwrap(response.release)

        XCTAssertEqual(response.code, 0)
        XCTAssertEqual(release.id, 9243)
        XCTAssertEqual(release.titleRu, "Стальной алхимик: Братство")
        XCTAssertEqual(release.titleOriginal, "Fullmetal Alchemist: Brotherhood")
        XCTAssertEqual(release.grade, 4.86)
        XCTAssertEqual(release.episodesReleased, 64)
        XCTAssertEqual(release.episodesTotal, 64)
        // `favorites_count` is the wire name; the Android field is favoriteCount.
        XCTAssertEqual(release.favoriteCount, 90421)
        XCTAssertEqual(release.profileListStatus, 1)
        XCTAssertEqual(release.isFavorite, true)
        XCTAssertEqual(release.isAdult, false)
        XCTAssertEqual(release.yourVote, 5)
        XCTAssertEqual(release.vote5Count, 106834)
        XCTAssertEqual(release.status?.name, "Завершён")
        XCTAssertEqual(release.category?.name, "Сериал")
        XCTAssertEqual(release.related?.releaseCount, 7)
        XCTAssertEqual(release.screenshotImages?.count, 2)
    }

    func testReleaseDisplayHelpers() throws {
        let release = try XCTUnwrap(Fixture.decode(ReleaseResponse.self, from: "release").release)

        XCTAssertEqual(release.displayTitle, "Стальной алхимик: Братство")
        XCTAssertEqual(release.displaySubtitle, "Fullmetal Alchemist: Brotherhood")
        XCTAssertEqual(release.genreList, ["Боевик", "Драма", "Приключения", "Фэнтези"])
        // 64 of 64 is a finished run, so the APK prints the total alone.
        XCTAssertEqual(release.episodeProgressText, "64 эп")
        XCTAssertEqual(release.seasonAndYear, "весна 2009")
        XCTAssertEqual(release.ageRatingText, "16+")
        XCTAssertEqual(release.ratingText, "4.9")
        XCTAssertEqual(release.listStatus, .watching)
        XCTAssertFalse(release.isPlaybackUnavailable)
        XCTAssertNil(release.playbackBlockedReason)
        XCTAssertEqual(release.continueWatchingText, "Серия 12 · AniLibria.TV")
        XCTAssertEqual(release.posterURL?.absoluteString, "https://static.anixart.tv/posters/9243.jpg")
    }

    func testDecodesEpisodesWithMixedKeyCasing() throws {
        let response = try Fixture.decode(EpisodeResponse.self, from: "episodes")
        let episodes = try XCTUnwrap(response.episodes)
        XCTAssertEqual(episodes.count, 2)

        let first = episodes[0]
        XCTAssertEqual(first.name, "Серия 1")
        XCTAssertEqual(first.position, 1)
        // The server sends no `id` here: the Android entity's is a Room row id,
        // so identity comes from the position instead. The fixture used to carry
        // an invented `id`, which is why this passed while the live API failed.
        XCTAssertEqual(first.id, 1)
        XCTAssertEqual(first.addedDate, 1238889600)   // camelCase on the wire
        XCTAssertEqual(first.isWatched, true)          // snake_case on the wire
        XCTAssertEqual(first.isFiller, false)
        XCTAssertTrue(first.isEmbed)
        XCTAssertNil(first.resumePosition)

        let second = episodes[1]
        XCTAssertEqual(second.id, 2)
        XCTAssertFalse(second.isEmbed)
        XCTAssertEqual(second.isFiller, true)
        // playbackPosition is milliseconds in the Android player.
        XCTAssertEqual(try XCTUnwrap(second.resumePosition), 435, accuracy: 0.001)
    }

    func testDecodesPolymorphicNotificationsAndToleratesUnknownKind() throws {
        let page = try Fixture.decode(PageableResponse<AnixartNotification>.self, from: "notifications")
        XCTAssertEqual(page.items.count, 3)
        XCTAssertTrue(page.isLastPage)

        guard case .episode(let episode) = page.items[0] else {
            return XCTFail("expected an episode notification first")
        }
        XCTAssertEqual(episode.episode?.name, "Серия 12")
        XCTAssertEqual(episode.episode?.release?.titleRu, "Стальной алхимик")
        XCTAssertEqual(episode.base.isNew, true)

        guard case .friend(let friend) = page.items[1] else {
            return XCTFail("expected a friend notification second")
        }
        XCTAssertEqual(friend.byProfile?.login, "kenji")

        // An unrecognised `type` must fall back rather than fail the whole page --
        // ProfileNotification declares a defaultImpl in the APK for exactly this.
        guard case .unsupported(let unknown) = page.items[2] else {
            return XCTFail("expected the unknown kind to fall back")
        }
        XCTAssertEqual(unknown.type, "someFutureKind")
        XCTAssertEqual(unknown.id, 53)
    }

    func testEpisodeCounterMatchesTheAndroidWording() throws {
        func text(released: Int?, total: Int?, statusId: Int? = nil) throws -> String? {
            var fields: [String] = []
            if let released { fields.append("\"episodes_released\":\(released)") }
            if let total { fields.append("\"episodes_total\":\(total)") }
            if let statusId { fields.append("\"status_id\":\(statusId)") }
            let json = "{\"id\":1\(fields.isEmpty ? "" : "," + fields.joined(separator: ","))}"
            return try JSONDecoder()
                .decode(Release.self, from: XCTUnwrap(json.data(using: .utf8)))
                .episodeProgressText
        }

        XCTAssertEqual(try text(released: 5, total: 12), "5 из 12 эп")
        XCTAssertEqual(try text(released: 154, total: nil), "154 из ? эп")
        XCTAssertEqual(try text(released: nil, total: 24), "? из 24 эп")
        // Finished run: the total alone, not "24 из 24".
        XCTAssertEqual(try text(released: 24, total: 24), "24 эп")
        // An announcement shows the planned total however far along it claims to be.
        XCTAssertEqual(try text(released: 0, total: 13, statusId: 3), "13 эп")
        XCTAssertEqual(try text(released: nil, total: nil, statusId: 3), "? эп")
        // Nothing known at all: the label is hidden.
        XCTAssertNil(try text(released: nil, total: nil))
    }

    func testFilterPresetsResolveIntoRanges() {
        // The preset index must not reach the wire; the server wants explicit bounds.
        XCTAssertEqual(FilterRequest(episodes: .from1to12).episodesFrom, 1)
        XCTAssertEqual(FilterRequest(episodes: .from1to12).episodesTo, 12)
        XCTAssertEqual(FilterRequest(episodes: .from13to25).episodesFrom, 13)
        XCTAssertEqual(FilterRequest(episodes: .from26to100).episodesTo, 100)
        // Open-ended preset sends no upper bound.
        XCTAssertEqual(FilterRequest(episodes: .over100).episodesFrom, 100)
        XCTAssertNil(FilterRequest(episodes: .over100).episodesTo)

        XCTAssertEqual(FilterRequest(episodeDuration: .upTo10).episodeDurationFrom, 1)
        XCTAssertEqual(FilterRequest(episodeDuration: .upTo10).episodeDurationTo, 10)
        XCTAssertEqual(FilterRequest(episodeDuration: .upTo30).episodeDurationFrom, 11)
        XCTAssertEqual(FilterRequest(episodeDuration: .over30).episodeDurationFrom, 31)
        XCTAssertNil(FilterRequest(episodeDuration: .over30).episodeDurationTo)

        // Empty strings are omitted rather than sent.
        XCTAssertNil(FilterRequest(country: "", studio: "").country)
        XCTAssertNil(FilterRequest(country: "", studio: "").studio)
        XCTAssertEqual(FilterRequest(source: .manga).source, "Манга")
    }

    func testPagingArithmetic() {
        let middle = PageableResponse<Release>(code: 0, content: [], currentPage: 1, totalPageCount: 5)
        XCTAssertEqual(middle.nextPage, 2)
        XCTAssertFalse(middle.isLastPage)

        let last = PageableResponse<Release>(code: 0, content: [], currentPage: 4, totalPageCount: 5)
        XCTAssertNil(last.nextPage)
        XCTAssertTrue(last.isLastPage)

        let empty = PageableResponse<Release>(code: 0, content: [], currentPage: 0, totalPageCount: 0)
        XCTAssertTrue(empty.isLastPage)
    }

    func testScheduleOrdersWeekdaysFromMonday() throws {
        let json = """
        {"code":0,"monday":[{"id":1}],"sunday":[{"id":7}],"wednesday":[]}
        """.data(using: .utf8)!
        let schedule = try JSONDecoder().decode(ScheduleResponse.self, from: json)
        let days = schedule.byWeekday
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first?.title, "Понедельник")
        XCTAssertEqual(days.first?.releases.first?.id, 1)
        XCTAssertEqual(days.last?.title, "Воскресенье")
        XCTAssertEqual(days.last?.releases.first?.id, 7)
        XCTAssertTrue(days[2].releases.isEmpty)
    }

    func testFriendStatusDecodesBothWireForms() throws {
        struct Holder: Codable { var friendStatus: FriendStatusCode? }
        let asInt = try JSONDecoder().decode(Holder.self, from: #"{"friendStatus":3}"#.data(using: .utf8)!)
        XCTAssertEqual(asInt.friendStatus, .friend)

        let asName = try JSONDecoder().decode(
            Holder.self,
            from: #"{"friendStatus":"PENDING_FIRST_SECOND"}"#.data(using: .utf8)!
        )
        XCTAssertEqual(asName.friendStatus, .requestSent)

        let unknown = try JSONDecoder().decode(Holder.self, from: #"{"friendStatus":"WHAT"}"#.data(using: .utf8)!)
        XCTAssertEqual(unknown.friendStatus, .unknown("WHAT"))
    }
}

/// `ReleaseComment.release` arrives in two shapes depending on the endpoint.
/// Decoding only the object shape made the release page fail against live data,
/// so both are locked in here.
final class EmbeddedReleaseTests: XCTestCase {
    private struct Wrapper: Codable {
        var release: EmbeddedRelease?
    }

    func testDecodesABareReleaseID() throws {
        let json = Data(#"{"release": 9243}"#.utf8)
        let wrapper = try JSONDecoder().decode(Wrapper.self, from: json)

        XCTAssertEqual(wrapper.release?.id, 9243)
        XCTAssertNil(wrapper.release?.value)
    }

    func testDecodesAWholeRelease() throws {
        let json = Data(#"{"release": {"id": 9243, "title_ru": "Стальной алхимик"}}"#.utf8)
        let wrapper = try JSONDecoder().decode(Wrapper.self, from: json)

        XCTAssertEqual(wrapper.release?.id, 9243)
        XCTAssertEqual(wrapper.release?.value?.titleRu, "Стальной алхимик")
    }

    func testDecodesAMissingRelease() throws {
        let json = Data(#"{"release": null}"#.utf8)
        let wrapper = try JSONDecoder().decode(Wrapper.self, from: json)

        // `release: null` decodes the key as absent, which is what Optional means here.
        XCTAssertNil(wrapper.release?.id)
        XCTAssertNil(wrapper.release?.value)
    }

    func testRoundTripsBothShapes() throws {
        let byID = EmbeddedRelease(value: nil, id: 7)
        let encoded = try JSONEncoder().encode(Wrapper(release: byID))
        XCTAssertEqual(try JSONDecoder().decode(Wrapper.self, from: encoded).release?.id, 7)
    }
}
