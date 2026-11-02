import Foundation
import SwiftUI
import XCTest
import AnixartKit
@testable import Anixart

final class RecentViewingMotionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private func release(age: TimeInterval, episode: Int? = 7) throws -> Release {
        let fields: [String: Any] = ["id":71, "last_view_timestamp": Int(now.timeIntervalSince1970 - age),
                                    "last_view_episode": episode.map { ["position": $0] } ?? [:]]
        return try JSONDecoder().decode(Release.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    func testRecentViewingUsesShortLocalizedAgeInsteadOfAbsoluteDate() throws {
        for (age, text) in [(0.0,"только что"), (59,"только что"), (60,"минуту назад"), (119,"минуту назад"),
                            (120,"2 мин назад"), (3599,"59 мин назад"), (3600,"час назад"),
                            (7199,"час назад"), (7200,"2 ч назад"), (86399,"23 ч назад")] {
            XCTAssertEqual(ReleaseHistoryMetadata.viewedAt(try release(age: age), now: now), text)
        }
    }

    func testOlderViewsRetainExactDateTimeAndTheEpisode() throws {
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let item = try release(age: 86400)
        let date = try XCTUnwrap(item.lastViewedDate)
        XCTAssertEqual(ReleaseHistoryMetadata.viewedAt(item, now: now, timeZone: utc), Format.dateTime(date, timeZone: utc))
        let otherZone = try XCTUnwrap(TimeZone(secondsFromGMT: 3 * 3600))
        XCTAssertEqual(ReleaseHistoryMetadata.viewedAt(item, now: now, timeZone: otherZone), Format.dateTime(date, timeZone: otherZone))
        XCTAssertTrue(ReleaseHistoryMetadata.subtitle(item, now: now, timeZone: utc)?.hasPrefix("7 серия • ") == true)
    }

    func testMissingDataAndFutureClockAnomaliesDoNotInventAPastView() throws {
        let unknown = try JSONDecoder().decode(Release.self, from: Data(#"{"id":71}"#.utf8))
        XCTAssertNil(ReleaseHistoryMetadata.viewedAt(unknown, now: now))
        let future = try release(age: -3600)
        let text = try XCTUnwrap(ReleaseHistoryMetadata.viewedAt(future, now: now))
        XCTAssertFalse(text.contains("назад"))
        XCTAssertEqual(ReleaseHistoryMetadata.viewedAt(try release(age: -30), now: now), "только что")
        XCTAssertEqual(ReleaseHistoryMetadata.subtitle(try release(age: 7200, episode: nil), now: now), "2 ч назад")
    }

    func testRecentAgeUpdatesAsTheInjectedClockAdvances() throws {
        let item = try release(age: 60)
        XCTAssertEqual(ReleaseHistoryMetadata.viewedAt(item, now: now), "минуту назад")
        XCTAssertEqual(ReleaseHistoryMetadata.viewedAt(item, now: now.addingTimeInterval(60)), "2 мин назад")
    }

    func testRecentViewingScheduleTicksOncePerMinuteAndDoesNotRepeatWhenPaused() {
        let active = RecentViewingTimelineSchedule(isActive: true)
        XCTAssertEqual(Array(active.entries(from: now, mode: .normal).prefix(3)),
                       [now, now.addingTimeInterval(60), now.addingTimeInterval(120)])
        let paused = RecentViewingTimelineSchedule(isActive: false)
        XCTAssertEqual(Array(paused.entries(from: now, mode: .normal)), [now])
    }

    func testMotionIsShortAndOptionalForReduceMotionAndResourceSaving() {
        let enabled = AppMotionPolicy(reduceMotion: false, resourceSaving: false)
        XCTAssertTrue(enabled.isEnabled)
        XCTAssertLessThanOrEqual(enabled.duration, 0.3)
        XCTAssertNotNil(enabled.animation)
        for policy in [AppMotionPolicy(reduceMotion: true, resourceSaving: false), AppMotionPolicy(reduceMotion: false, resourceSaving: true)] {
            XCTAssertFalse(policy.isEnabled)
            XCTAssertEqual(policy.duration, 0)
            XCTAssertNil(policy.animation)
        }
    }
}
