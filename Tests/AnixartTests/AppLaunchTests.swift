import Foundation
import UIKit
import XCTest
import AnixartKit
@testable import Anixart

final class AppLaunchTests: XCTestCase {
    private let policy = AppLaunchPolicy(
        configurationTimeout: .seconds(1), sessionTimeout: .seconds(2), firstPageTimeout: .seconds(3)
    )

    private func isolatedDefaults() throws -> (defaults: UserDefaults, suite: String) {
        let suite = "AppLaunchTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }

    private func page(_ ids: [Int]) -> String {
        let rows = ids.map { "{\"id\":\($0)}" }.joined(separator: ",")
        return "{\"code\":0,\"content\":[\(rows)],\"current_page\":0,\"total_page_count\":1}"
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    private func token(_ request: URLRequest) -> String? {
        request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == "token" }?.value
    }

    @MainActor
    private func enqueueConfiguration(_ rig: ProfileTestRig) {
        rig.api.enqueue("/config/urls", json: #"{"code":0}"#)
        rig.api.enqueue("/config/toggles", json: #"{"code":0}"#)
    }

    @MainActor
    private func launch(
        _ rig: ProfileTestRig, defaults: UserDefaults, clock: AppLaunchTestClock,
        screen: LaunchScreen = .home,
        loadConfiguration: (@MainActor @Sendable () async throws -> Void)? = nil,
        restoreSession: (@MainActor @Sendable () async throws -> Void)? = nil
    ) -> AppLaunchCoordinator {
        AppLaunchCoordinator(
            session: rig.session, screen: screen, defaults: defaults, policy: policy,
            deadline: AppLaunchDeadline { try await clock.sleep(for: $0) },
            loadConfiguration: loadConfiguration, restoreSession: restoreSession
        )
    }

    @MainActor
    func testConfigAndRestoreFinishBeforeSavedPresetWarmsAndHandoffDoesNotReload() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        HomePreferences(defaults: defaults).setDefaultTab(.donghua)
        let rig = ProfileTestRig()
        let clock = AppLaunchTestClock()
        defer { clock.close() }
        let config = rig.api.hold("/config/urls")
        let firstPage = rig.api.hold("/filter/0")
        defer { config.respond("{}", status: 500); firstPage.respond("{}", status: 500) }
        rig.api.enqueue("/config/toggles", json: #"{"code":0}"#)
        let coordinator = launch(rig, defaults: defaults, clock: clock)
        let start = Task { await coordinator.startIfNeeded() }
        defer { start.cancel() }
        await fulfillment(of: [config.arrived], timeout: 5)
        XCTAssertEqual(coordinator.phase, .loadingConfiguration)
        XCTAssertEqual(rig.session.state, .loading)
        XCTAssertTrue(rig.api.requests(to: "/filter/0").isEmpty)
        config.respond(#"{"code":0}"#)
        await fulfillment(of: [firstPage.arrived], timeout: 5)
        XCTAssertEqual(coordinator.phase, .loadingHome)
        XCTAssertFalse(coordinator.isReady)
        XCTAssertEqual(rig.session.state, .guest)
        XCTAssertEqual(try body(XCTUnwrap(firstPage.request))["country"] as? String, "Китай")
        firstPage.respond(page([71, 72]))
        await start.value

        let key = ReleaseFeedKey(filter: try XCTUnwrap(HomeTab.donghua.filter), viewer: rig.session.viewerKey)
        let warmed = try XCTUnwrap(coordinator.prewarmedHomeFeed(for: .donghua, key: key))
        XCTAssertTrue(coordinator.isReady)
        XCTAssertEqual(warmed.paginator.items.map(\.id), [71, 72])
        let adopted = try XCTUnwrap(coordinator.takePrewarmedHomeFeed(for: .donghua, key: key))
        XCTAssertTrue(adopted === warmed)
        XCTAssertNil(coordinator.takePrewarmedHomeFeed(for: .donghua, key: key))
        await adopted.paginator.loadFirstPageIfNeeded()
        // Repeated root tasks model reappearance/resume; neither config nor feed
        // restarts, and the device's separately saved starting tab is not changed.
        await coordinator.startIfNeeded()
        await coordinator.startIfNeeded()
        XCTAssertEqual(rig.api.requests.map { $0.url?.path }, ["/config/urls", "/config/toggles", "/filter/0"])
        XCTAssertEqual(HomePreferences(defaults: defaults).defaultTab, .donghua)
        XCTAssertFalse(rig.session.isPresentingAuth)
    }

    @MainActor
    func testConfiguredCustomFeedKeepsExactScopeAndGuestOmitsOnlyAccountExclusions() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = HomePreferences(defaults: defaults)
        var custom = CustomTabFilter()
        custom.country = "Китай"
        custom.genres = ["драма"]
        custom.profileListExclusions = [.completed]
        preferences.save(customFilter: custom)
        preferences.setDefaultTab(.custom)
        let rig = ProfileTestRig()
        let clock = AppLaunchTestClock()
        defer { clock.close() }
        enqueueConfiguration(rig)
        rig.api.enqueue("/filter/0", json: page([71]))
        let coordinator = launch(rig, defaults: defaults, clock: clock)
        await coordinator.startIfNeeded()

        let key = ReleaseFeedKey(filter: custom.filterRequest, viewer: rig.session.viewerKey)
        let warmed = try XCTUnwrap(coordinator.prewarmedHomeFeed(for: .custom, key: key))
        XCTAssertEqual(warmed.filter, custom.filterRequest)
        XCTAssertNil(coordinator.prewarmedHomeFeed(for: .latest, key: key), "A matching filter does not make another tab eligible")
        XCTAssertNil(coordinator.prewarmedHomeFeed(for: .custom, key: ReleaseFeedKey(
            filter: FilterRequest(country: "Япония"), viewer: key.viewer)))
        XCTAssertNil(coordinator.prewarmedHomeFeed(for: .custom, key: ReleaseFeedKey(
            filter: key.filter, viewer: ProfileViewerKey(account: nil, revision: key.viewer.revision + 1))))
        let request = try XCTUnwrap(rig.api.requests(to: "/filter/0").first)
        let json = try body(request)
        XCTAssertEqual(json["country"] as? String, "Китай")
        XCTAssertEqual(json["genres"] as? [String], ["драма"])
        XCTAssertEqual(json["genres_mode"] as? Int, 1)
        XCTAssertNil(json["profile_list_exclusions"])
        XCTAssertNil(token(request))
        XCTAssertEqual(HomePreferences(defaults: defaults).customFilter, custom)
        XCTAssertTrue(coordinator.takePrewarmedHomeFeed(for: .custom, key: key) === warmed)
        await warmed.paginator.loadFirstPageIfNeeded()
        XCTAssertEqual(rig.api.requests(to: "/filter/0").count, 1)
        XCTAssertFalse(rig.session.isPresentingAuth)
    }

    @MainActor
    func testUnsetCustomDefaultHasNoUnfilteredWarmRequest() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        HomePreferences(defaults: defaults).setDefaultTab(.custom)
        let rig = ProfileTestRig()
        let clock = AppLaunchTestClock()
        defer { clock.close() }
        enqueueConfiguration(rig)
        let coordinator = launch(rig, defaults: defaults, clock: clock)
        await coordinator.startIfNeeded()
        XCTAssertTrue(coordinator.isReady)
        XCTAssertTrue(rig.api.requests(to: "/filter/0").isEmpty)
        XCTAssertNil(AppLaunchHomeTarget.resolve(screen: .home, preferences: HomePreferences(defaults: defaults)))
        XCTAssertNil(HomePreferences(defaults: defaults).customFilter)
    }

    @MainActor
    func testConfiguredEmptyCustomDefaultIsDifferentFromUnsetAndDoesWarm() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = HomePreferences(defaults: defaults)
        preferences.setDefaultTab(.custom)
        preferences.save(customFilter: CustomTabFilter())
        let rig = ProfileTestRig()
        let clock = AppLaunchTestClock()
        defer { clock.close() }
        enqueueConfiguration(rig)
        rig.api.enqueue("/filter/0", json: page([]))
        let coordinator = launch(rig, defaults: defaults, clock: clock)
        await coordinator.startIfNeeded()
        let key = ReleaseFeedKey(filter: CustomTabFilter().filterRequest, viewer: rig.session.viewerKey)
        let warmed = try XCTUnwrap(coordinator.takePrewarmedHomeFeed(for: .custom, key: key))
        XCTAssertTrue(warmed.paginator.hasLoaded)
        XCTAssertTrue(warmed.paginator.isEmpty)
        await warmed.paginator.loadFirstPageIfNeeded()
        XCTAssertEqual(rig.api.requests(to: "/filter/0").count, 1)
    }

    @MainActor
    func testNonHomeSmokeRoutesDoNotWarmHomeEvenWhenTheirRootTabIsHome() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let routes: [LaunchScreen] = [.profile, .feed, .release(71), .randomRelease, .player(71), .kodik(71)]
        for route in routes {
            let rig = ProfileTestRig()
            let clock = AppLaunchTestClock()
            defer { clock.close() }
            enqueueConfiguration(rig)
            let coordinator = launch(rig, defaults: defaults, clock: clock, screen: route)
            await coordinator.startIfNeeded()
            XCTAssertTrue(coordinator.isReady, "\(route)")
            XCTAssertEqual(rig.api.requests.map { $0.url?.path }, ["/config/urls", "/config/toggles"], "\(route)")
            XCTAssertFalse(rig.session.isPresentingAuth)
        }
    }

    @MainActor
    func testFirstPageFailureIsHandedOffWithNormalRetryAndNoAutomaticSecondLoad() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let rig = ProfileTestRig()
        let clock = AppLaunchTestClock()
        defer { clock.close() }
        enqueueConfiguration(rig)
        rig.api.enqueue("/filter/0", json: #"{"code":2}"#)
        let coordinator = launch(rig, defaults: defaults, clock: clock)
        await coordinator.startIfNeeded()
        let key = ReleaseFeedKey(filter: try XCTUnwrap(HomeTab.anime.filter), viewer: rig.session.viewerKey)
        let warmed = try XCTUnwrap(coordinator.takePrewarmedHomeFeed(for: .anime, key: key))
        XCTAssertTrue(coordinator.isReady)
        XCTAssertNotNil(warmed.paginator.errorMessage)
        XCTAssertEqual(warmed.paginator.failedPage, 0)
        XCTAssertFalse(warmed.paginator.isLoadingFirstPage)
        await warmed.paginator.loadFirstPageIfNeeded()
        XCTAssertEqual(rig.api.requests(to: "/filter/0").count, 1)
        rig.api.enqueue("/filter/0", json: page([72]))
        await warmed.paginator.retry()
        XCTAssertEqual(warmed.paginator.items.map(\.id), [72])
        XCTAssertNil(warmed.paginator.errorMessage)
        XCTAssertEqual(rig.api.requests(to: "/filter/0").count, 2)
        XCTAssertTrue(coordinator.isReady)
    }

    @MainActor
    func testWarmDeadlineCancelsTransportAndKeepsRetryableFailureWithoutLimitingLaterPages() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let rig = ProfileTestRig()
        let clock = AppLaunchTestClock()
        defer { clock.close() }
        enqueueConfiguration(rig)
        let held = rig.api.hold("/filter/0")
        defer { held.respond("{}", status: 500) }
        let coordinator = launch(rig, defaults: defaults, clock: clock)
        let finished = expectation(description: "Launch leaves timed-out first page")
        let start = Task { await coordinator.startIfNeeded(); finished.fulfill() }
        defer { start.cancel() }
        await fulfillment(of: [held.arrived, clock.armed(for: policy.firstPageTimeout)], timeout: 5)
        XCTAssertEqual(coordinator.phase, .loadingHome)
        clock.expire(policy.firstPageTimeout)
        await fulfillment(of: [finished, held.cancelled], timeout: 5)
        await start.value
        let key = ReleaseFeedKey(filter: try XCTUnwrap(HomeTab.anime.filter), viewer: rig.session.viewerKey)
        let warmed = try XCTUnwrap(coordinator.takePrewarmedHomeFeed(for: .anime, key: key))
        XCTAssertTrue(coordinator.isReady)
        XCTAssertEqual(warmed.paginator.failedPage, 0)
        XCTAssertFalse(warmed.paginator.isLoadingFirstPage)
        XCTAssertTrue(warmed.paginator.errorMessage?.contains("Время ожидания истекло") == true)
        await warmed.paginator.loadFirstPageIfNeeded()
        XCTAssertEqual(rig.api.requests(to: "/filter/0").count, 1)
        held.respond(page([999])) // A cancelled launch reply cannot populate retry.
        rig.api.enqueue("/filter/0", json: page(Array(1...25)))
        await warmed.paginator.retry()
        rig.api.enqueue("/filter/1", json: page([26]))
        await warmed.paginator.loadNextPage()
        XCTAssertEqual(warmed.paginator.items.map(\.id), Array(1...26))
        XCTAssertNil(warmed.paginator.errorMessage)
        XCTAssertEqual(clock.sleepCount(for: policy.firstPageTimeout), 1, "Only the warm attempt uses the launch deadline")
    }

    @MainActor
    func testStoredSessionRestoresBeforeWarmAndFeedUsesOnlyItsOwningToken() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var custom = CustomTabFilter()
        custom.profileListExclusions = [.completed]
        let preferences = HomePreferences(defaults: defaults)
        preferences.setDefaultTab(.custom)
        preferences.save(customFilter: custom)
        let store = InMemoryTokenStore(token: "stored-owner", profileID: 42)
        let rig = ProfileTestRig(store: store)
        let clock = AppLaunchTestClock()
        defer { clock.close() }
        enqueueConfiguration(rig)
        let profile = rig.api.hold("/profile/42")
        defer { profile.respond("{}", status: 500) }
        rig.api.enqueue("/filter/0", json: page([71]))
        let coordinator = launch(rig, defaults: defaults, clock: clock)
        let start = Task { await coordinator.startIfNeeded() }
        defer { start.cancel() }
        await fulfillment(of: [profile.arrived], timeout: 5)
        XCTAssertEqual(coordinator.phase, .restoringSession)
        XCTAssertTrue(rig.api.requests(to: "/filter/0").isEmpty)
        profile.respond(#"{"code":0,"profile":{"id":42}}"#)
        await start.value
        let key = ReleaseFeedKey(filter: custom.filterRequest, viewer: rig.session.viewerKey)
        let warmed = try XCTUnwrap(coordinator.takePrewarmedHomeFeed(for: .custom, key: key))
        XCTAssertEqual(warmed.viewer.account?.profileID, 42)
        let request = try XCTUnwrap(rig.api.requests(to: "/filter/0").first)
        XCTAssertEqual(token(request), "stored-owner")
        XCTAssertEqual(try body(request)["profile_list_exclusions"] as? [Int], [3])
        XCTAssertEqual(rig.api.requests.map { $0.url?.path },
                       ["/config/urls", "/config/toggles", "/profile/42", "/notification/count", "/filter/0"])
        let storedToken = await store.token()
        XCTAssertEqual(storedToken, "stored-owner")
        XCTAssertTrue(rig.api.requests(to: "/auth/signIn").isEmpty)
        XCTAssertFalse(rig.session.isPresentingAuth)
    }

    @MainActor
    func testSlowSessionSupplementaryReadCannotTrapLaunchOrEraseStoredCredentials() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = InMemoryTokenStore(token: "stored-owner", profileID: 42)
        let rig = ProfileTestRig(store: store)
        let clock = AppLaunchTestClock()
        defer { clock.close() }
        enqueueConfiguration(rig)
        let profile = rig.api.hold("/profile/42")
        defer { profile.respond("{}", status: 500) }
        rig.api.enqueue("/filter/0", json: page([71]))
        let coordinator = launch(rig, defaults: defaults, clock: clock)
        let finished = expectation(description: "Launch passes session deadline")
        let start = Task { await coordinator.startIfNeeded(); finished.fulfill() }
        defer { start.cancel() }
        await fulfillment(of: [profile.arrived, clock.armed(for: policy.sessionTimeout)], timeout: 5)
        clock.expire(policy.sessionTimeout)
        await fulfillment(of: [finished, profile.cancelled], timeout: 5)
        await start.value
        XCTAssertTrue(coordinator.isReady)
        XCTAssertEqual(rig.session.currentProfileID, 42)
        XCTAssertEqual(token(try XCTUnwrap(rig.api.requests(to: "/filter/0").first)), "stored-owner")
        let storedToken = await store.token()
        let storedID = await store.profileID()
        XCTAssertEqual(storedToken, "stored-owner")
        XCTAssertEqual(storedID, 42)
        XCTAssertFalse(rig.session.isPresentingAuth)
    }

    @MainActor
    func testViewerChangeDuringWarmRejectsLatePageAndNeverBorrowsNewLoginToken() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let rig = ProfileTestRig()
        let clock = AppLaunchTestClock()
        defer { clock.close() }
        enqueueConfiguration(rig)
        let held = rig.api.hold("/filter/0")
        defer { held.respond("{}", status: 500) }
        let coordinator = launch(rig, defaults: defaults, clock: clock)
        let start = Task { await coordinator.startIfNeeded() }
        defer { start.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        let guest = rig.session.viewerKey
        try await rig.signIn(token: "later-owner") // .invalid mock API only.
        held.respond(page([71]))
        await start.value
        let filter = try XCTUnwrap(HomeTab.anime.filter)
        XCTAssertTrue(coordinator.isReady)
        XCTAssertNil(token(try XCTUnwrap(held.request)))
        XCTAssertNil(coordinator.prewarmedHomeFeed(for: .anime, key: ReleaseFeedKey(filter: filter, viewer: guest)))
        XCTAssertNil(coordinator.prewarmedHomeFeed(for: .anime, key: ReleaseFeedKey(filter: filter, viewer: rig.session.viewerKey)))
        await coordinator.startIfNeeded()
        XCTAssertEqual(rig.api.requests(to: "/filter/0").count, 1)
        rig.api.enqueue("/filter/0", json: page([72]))
        let current = ReleaseFeedModel(filter: filter, session: rig.session)
        await current.paginator.loadFirstPageIfNeeded()
        XCTAssertEqual(current.paginator.items.map(\.id), [72])
        XCTAssertEqual(token(try XCTUnwrap(rig.api.requests(to: "/filter/0").last)), "later-owner")
    }

    @MainActor
    func testCompletedWarmCacheAndItsPaginatorCannotBeUsedByLaterViewer() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let rig = ProfileTestRig()
        let clock = AppLaunchTestClock()
        defer { clock.close() }
        enqueueConfiguration(rig)
        rig.api.enqueue("/filter/0", json: page([71]))
        let coordinator = launch(rig, defaults: defaults, clock: clock)
        await coordinator.startIfNeeded()
        let filter = try XCTUnwrap(HomeTab.anime.filter)
        let oldKey = ReleaseFeedKey(filter: filter, viewer: rig.session.viewerKey)
        let old = try XCTUnwrap(coordinator.prewarmedHomeFeed(for: .anime, key: oldKey))
        try await rig.signIn(token: "later-owner")
        let currentKey = ReleaseFeedKey(filter: filter, viewer: rig.session.viewerKey)
        XCTAssertNil(coordinator.prewarmedHomeFeed(for: .anime, key: oldKey))
        XCTAssertNil(coordinator.prewarmedHomeFeed(for: .anime, key: currentKey))
        await old.paginator.reload()
        XCTAssertEqual(rig.api.requests(to: "/filter/0").count, 1)
        coordinator.discardPrewarmedFeed(ifViewerChangedTo: currentKey.viewer)
        XCTAssertNil(coordinator.takePrewarmedHomeFeed(for: .anime, key: currentKey))
        XCTAssertTrue(coordinator.isReady)
    }

    @MainActor
    func testLocalDefaultIsReadAfterRestoreAndMismatchingHandoffDiscardsWarmResult() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let rig = ProfileTestRig()
        let clock = AppLaunchTestClock()
        defer { clock.close() }
        enqueueConfiguration(rig)
        rig.api.enqueue("/filter/0", json: page([71]))
        let coordinator = launch(rig, defaults: defaults, clock: clock, restoreSession: {
            await rig.session.restore()
            HomePreferences(defaults: defaults).setDefaultTab(.movies)
        })
        await coordinator.startIfNeeded()
        let key = ReleaseFeedKey(filter: try XCTUnwrap(HomeTab.movies.filter), viewer: rig.session.viewerKey)
        XCTAssertNotNil(coordinator.prewarmedHomeFeed(for: .movies, key: key))
        XCTAssertEqual(try body(XCTUnwrap(rig.api.requests(to: "/filter/0").first))["category_id"] as? Int, 2)
        XCTAssertNil(coordinator.takePrewarmedHomeFeed(for: .anime, key: key))
        XCTAssertNil(coordinator.prewarmedHomeFeed(for: .movies, key: key), "A mismatch must not turn launch into a later-visit cache")
        await coordinator.startIfNeeded()
        XCTAssertEqual(rig.api.requests(to: "/filter/0").count, 1)
        XCTAssertEqual(HomePreferences(defaults: defaults).defaultTab, .movies)
    }

    @MainActor
    func testCancellationOfSwiftUIWaiterDoesNotCancelOrReplayTheOwnedColdStart() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let rig = ProfileTestRig()
        let clock = AppLaunchTestClock()
        defer { clock.close() }
        let gate = ProfileTestGate()
        defer { gate.release() }
        rig.api.enqueue("/filter/0", json: page([71]))
        let configurationCalls = AppLaunchTestCounter()
        let coordinator = launch(rig, defaults: defaults, clock: clock, loadConfiguration: {
            configurationCalls.value += 1
            await gate.wait()
            try Task.checkCancellation()
        })
        let first = Task { await coordinator.startIfNeeded() }
        defer { first.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        first.cancel()
        let second = Task { await coordinator.startIfNeeded() }
        defer { second.cancel() }
        gate.release()
        await first.value
        await second.value
        await coordinator.startIfNeeded()
        XCTAssertTrue(coordinator.isReady)
        XCTAssertEqual(configurationCalls.value, 1)
        XCTAssertEqual(rig.api.requests(to: "/filter/0").count, 1)
        XCTAssertEqual(rig.session.state, .guest)
    }

    @MainActor
    func testConfigAndSessionDeadlinesDoNotAwaitUncooperativeLateCompletions() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let rig = ProfileTestRig()
        await rig.session.restore()
        let clock = AppLaunchTestClock()
        defer { clock.close() }
        let config = ProfileTestGate()
        let session = ProfileTestGate()
        defer { config.release(); session.release() }
        rig.api.enqueue("/filter/0", json: page([71]))
        let coordinator = launch(rig, defaults: defaults, clock: clock,
                                 loadConfiguration: { await config.wait() }, restoreSession: { await session.wait() })
        let finished = expectation(description: "Launch ready without late callbacks")
        let start = Task { await coordinator.startIfNeeded(); finished.fulfill() }
        defer { start.cancel() }
        await fulfillment(of: [config.entered, clock.armed(for: policy.configurationTimeout)], timeout: 5)
        clock.expire(policy.configurationTimeout)
        await fulfillment(of: [session.entered, clock.armed(for: policy.sessionTimeout)], timeout: 5)
        XCTAssertTrue(rig.api.requests(to: "/filter/0").isEmpty)
        clock.expire(policy.sessionTimeout)
        await fulfillment(of: [finished], timeout: 5)
        let readyBeforeCallbacks = coordinator.isReady
        // Release even on expectation failure so a broken task-group implementation
        // fails deterministically rather than hanging the XCTest process.
        config.release()
        session.release()
        await start.value
        XCTAssertTrue(readyBeforeCallbacks)
        XCTAssertEqual(rig.api.requests(to: "/filter/0").count, 1)
        await coordinator.startIfNeeded()
        XCTAssertTrue(coordinator.isReady)
    }

    @MainActor
    func testConfigurationDeadlineKeepsFallbackHostAndDoesNotBeginAnotherConfigRequest() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let rig = ProfileTestRig()
        let clock = AppLaunchTestClock()
        defer { clock.close() }
        let config = rig.api.hold("/config/urls")
        defer { config.respond("{}", status: 500) }
        rig.api.enqueue("/filter/0", json: page([71]))
        let coordinator = launch(rig, defaults: defaults, clock: clock)
        let finished = expectation(description: "Launch continues after configuration deadline")
        let start = Task { await coordinator.startIfNeeded(); finished.fulfill() }
        defer { start.cancel() }
        await fulfillment(of: [config.arrived, clock.armed(for: policy.configurationTimeout)], timeout: 5)
        clock.expire(policy.configurationTimeout)
        await fulfillment(of: [finished, config.cancelled], timeout: 5)
        await start.value
        config.respond(#"{"code":0,"apiUrls":["https://late-config.invalid/"]}"#)
        XCTAssertTrue(coordinator.isReady)
        XCTAssertEqual(rig.session.state, .guest)
        XCTAssertNil(rig.session.toggles)
        let configuration = await rig.client.currentConfiguration
        XCTAssertEqual(configuration.baseURL, rig.api.baseURL)
        XCTAssertEqual(rig.api.requests.map { $0.url?.path }, ["/config/urls", "/filter/0"])
    }

    @MainActor
    func testCancelledConfigurationApplyCannotReplaceTheCurrentHost() async throws {
        let rig = ProfileTestRig()
        let gate = ProfileTestGate()
        defer { gate.release() }
        let urls = try profileTestDecode(ConfigUrlsResponse.self,
                                         #"{"code":0,"apiUrls":["https://late-config.invalid/"]}"#)
        let applying = Task { await gate.wait(); await rig.client.apply(urls) }
        defer { applying.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        applying.cancel()
        gate.release()
        await applying.value
        let configuration = await rig.client.currentConfiguration
        XCTAssertEqual(configuration.baseURL, rig.api.baseURL)
        XCTAssertTrue(rig.api.requests.isEmpty)
    }

    @MainActor
    func testSlowCredentialReadSettlesAsGuestWithoutErasingOrLatePublishingTheStoredOwner() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppLaunchHeldReadTokenStore()
        defer { store.readGate.release() }
        let rig = ProfileTestRig(store: store)
        let clock = AppLaunchTestClock()
        defer { clock.close() }
        enqueueConfiguration(rig)
        rig.api.enqueue("/filter/0", json: page([71]))
        let restored = expectation(description: "Late cancelled credential read finished")
        let coordinator = launch(rig, defaults: defaults, clock: clock, restoreSession: {
            await rig.session.restore()
            restored.fulfill()
        })
        let finished = expectation(description: "Launch settles without waiting for credential store")
        let start = Task { await coordinator.startIfNeeded(); finished.fulfill() }
        defer { start.cancel() }
        await fulfillment(of: [store.readGate.entered, clock.armed(for: policy.sessionTimeout)], timeout: 5)
        clock.expire(policy.sessionTimeout)
        await fulfillment(of: [finished], timeout: 5)
        await start.value
        XCTAssertTrue(coordinator.isReady)
        XCTAssertEqual(rig.session.state, .guest)
        let guest = rig.session.viewerKey
        let key = ReleaseFeedKey(filter: try XCTUnwrap(HomeTab.anime.filter), viewer: guest)
        XCTAssertNotNil(coordinator.prewarmedHomeFeed(for: .anime, key: key))
        XCTAssertNil(token(try XCTUnwrap(rig.api.requests(to: "/filter/0").first)))
        store.readGate.release()
        await fulfillment(of: [restored], timeout: 5)
        XCTAssertEqual(rig.session.viewerKey, guest)
        XCTAssertEqual(rig.session.state, .guest)
        let storedID = await store.profileID()
        let storedToken = await store.token()
        let writes = await store.writes
        XCTAssertEqual(storedID, 42)
        XCTAssertEqual(storedToken, "stored-owner")
        XCTAssertEqual(writes, 0)
        XCTAssertTrue(rig.api.requests(to: "/profile/42").isEmpty)
        XCTAssertFalse(rig.session.isPresentingAuth)
    }

    func testLaunchLimitsAndMotionAreSmallAndHaveNoMinimumDelay() {
        let policy = AppLaunchPolicy()
        XCTAssertEqual(policy.configurationTimeout, .seconds(4))
        XCTAssertEqual(policy.sessionTimeout, .seconds(4))
        XCTAssertEqual(policy.firstPageTimeout, .seconds(12))
        let normal = AppLaunchPresentation.motionPolicy(reduceMotion: false, resourceSaving: false, lowPower: false)
        XCTAssertEqual(normal, AppMotionPolicy(reduceMotion: false, resourceSaving: false))
        XCTAssertGreaterThan(normal.duration, 0)
        XCTAssertLessThanOrEqual(normal.duration, 0.25)
        XCTAssertEqual(AppLaunchPresentation.motionPolicy(reduceMotion: true, resourceSaving: false, lowPower: false).duration, 0)
        XCTAssertEqual(AppLaunchPresentation.motionPolicy(reduceMotion: false, resourceSaving: true, lowPower: false).duration, 0)
        XCTAssertEqual(AppLaunchPresentation.motionPolicy(reduceMotion: false, resourceSaving: false, lowPower: true).duration, 0)
    }

    @MainActor
    func testNativeLaunchResourceMatchesRuntimeMarkAndFullScreenCenterAcrossSizes() throws {
        let bundle = Bundle(for: AppEnvironment.self)
        guard bundle.url(forResource: "LaunchScreen", withExtension: "storyboardc") != nil else {
            XCTFail("The native launch storyboard must be in app resources")
            return
        }
        let image = try XCTUnwrap(UIImage(named: AppLaunchPresentation.markName, in: bundle, compatibleWith: nil))
        XCTAssertEqual(image.size.width, image.size.height)
        XCTAssertNotNil(UIColor(named: AppLaunchPresentation.backgroundName, in: bundle, compatibleWith: nil))
        let controller = try XCTUnwrap(UIStoryboard(name: "LaunchScreen", bundle: bundle).instantiateInitialViewController())
        controller.loadViewIfNeeded()
        let mark = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UIImageView }.first)
        for size in [CGSize(width: 390, height: 844), CGSize(width: 844, height: 390), CGSize(width: 1024, height: 768)] {
            controller.view.frame = CGRect(origin: .zero, size: size)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            XCTAssertEqual(mark.bounds.width, AppLaunchPresentation.markSide, accuracy: 0.5)
            XCTAssertEqual(mark.bounds.height, AppLaunchPresentation.markSide, accuracy: 0.5)
            XCTAssertEqual(mark.center.x, size.width / 2, accuracy: 0.5)
            XCTAssertEqual(mark.center.y, size.height / 2, accuracy: 0.5)
        }
    }
}

@MainActor
private final class AppLaunchTestCounter {
    var value = 0
}

private actor AppLaunchHeldReadTokenStore: TokenStore {
    nonisolated let readGate = ProfileTestGate()
    private(set) var writes = 0

    func token() async -> String? { "stored-owner" }
    func profileID() async -> Int? { await readGate.wait(); return 42 }
    func save(token: String, profileID: Int) async throws { writes += 1 }
    func replace(token: String, profileID: Int, expectedToken: String) async throws -> Bool { writes += 1; return false }
    func clear() async throws { writes += 1 }
}

/// Manually fired, cancellation-aware deadline clock. No test waits for a real
/// sleep or contacts a real host; ProfileTestRig intercepts every .invalid request.
private final class AppLaunchTestClock: @unchecked Sendable {
    private struct Waiter {
        let duration: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var waiters: [UUID: Waiter] = [:]
    private var expectations: [Duration: XCTestExpectation] = [:]
    private var armedDurations: Set<Duration> = []
    private var expired: Set<Duration> = []
    private var sleeps: [Duration] = []
    private var closed = false

    func armed(for duration: Duration) -> XCTestExpectation {
        lock.lock()
        defer { lock.unlock() }
        return expectation(for: duration)
    }

    private func expectation(for duration: Duration) -> XCTestExpectation {
        if let expectation = expectations[duration] { return expectation }
        let expectation = XCTestExpectation(description: "Armed launch deadline \(duration)")
        expectations[duration] = expectation
        return expectation
    }

    func sleepCount(for duration: Duration) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return sleeps.filter { $0 == duration }.count
    }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                sleeps.append(duration)
                let notify = armedDurations.insert(duration).inserted
                let expectation = expectation(for: duration)
                let immediate: Result<Void, Error>?
                if closed || Task.isCancelled { immediate = .failure(CancellationError()) }
                else if expired.contains(duration) { immediate = .success(()) }
                else {
                    waiters[id] = Waiter(duration: duration, continuation: continuation)
                    immediate = nil
                }
                lock.unlock()
                if notify { expectation.fulfill() }
                if let immediate { continuation.resume(with: immediate) }
            }
        } onCancel: { self.cancel(id) }
    }

    func expire(_ duration: Duration) {
        lock.lock()
        expired.insert(duration)
        let matching = waiters.filter { $0.value.duration == duration }
        for id in matching.keys { waiters[id] = nil }
        lock.unlock()
        for waiter in matching.values { waiter.continuation.resume() }
    }

    func close() {
        lock.lock()
        closed = true
        let pending = waiters.values.map(\.continuation)
        waiters = [:]
        lock.unlock()
        for continuation in pending { continuation.resume(throwing: CancellationError()) }
    }

    private func cancel(_ id: UUID) {
        lock.lock()
        let waiter = waiters.removeValue(forKey: id)
        lock.unlock()
        waiter?.continuation.resume(throwing: CancellationError())
    }
}
