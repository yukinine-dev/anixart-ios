import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class EpisodeSelectionScopeTests: XCTestCase {
    private func type(_ id: Int = 1) throws -> EpisodeType {
        try profileTestDecode(EpisodeType.self, "{\"id\":\(id),\"name\":\"Voice \(id)\"}")
    }

    private func episodes(_ name: String, watched: Bool = false) -> String {
        "{\"code\":0,\"episodes\":[{\"position\":1,\"name\":\"\(name)1\",\"is_watched\":\(watched)},"
            + "{\"position\":2,\"name\":\"\(name)2\",\"is_watched\":\(watched)}]}"
    }

    @MainActor
    private func makeModel(_ rig: ProfileTestRig) throws -> EpisodePickerViewModel {
        EpisodePickerViewModel(release: try profileTestDecode(Release.self, #"{"id":71}"#), session: rig.session)
    }

    @MainActor
    private func readyModel(_ rig: ProfileTestRig, watched: Bool = false) async throws -> EpisodePickerViewModel {
        let model = try makeModel(rig)
        rig.api.enqueue("/episode/71/1", json: #"{"code":0,"sources":[{"id":10,"name":"A"},{"id":20,"name":"B"}]}"#)
        rig.api.enqueue("/episode/71/1/10", json: episodes("A", watched: watched))
        rig.api.enqueue("/episode/71/1/20", json: episodes("B", watched: watched))
        try await model.select(type: type())
        return model
    }

    @MainActor
    func testMissingEpisodeIDsAreFilledFromTheirReleaseAndHostingRequest() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let model = try await readyModel(rig)
        XCTAssertEqual(model.selectedSource?.id, 10)
        XCTAssertEqual(model.episodes.map(\.releaseId), [71, 71])
        XCTAssertEqual(model.episodes.map(\.sourceId), [10, 10])
        let other = try XCTUnwrap(model.sources.first { $0.id == 20 })
        await model.select(source: other)
        XCTAssertEqual(model.episodes.map(\.sourceId), [20, 20])
        XCTAssertEqual(model.episodes.map(\.name), ["B1", "B2"])
    }

    @MainActor
    func testExplicitHostingAndNewerDirectLoadWinOverDelayedPrefetch() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = try makeModel(rig)
        rig.api.enqueue("/episode/71/1", json: #"{"code":0,"sources":[{"id":10,"name":"A"},{"id":20,"name":"B"}]}"#)
        let slow = rig.api.hold("/episode/71/1/10")
        defer { slow.respond("{}", status: 500) }
        rig.api.enqueue("/episode/71/1/20", json: episodes("Old"))
        let voice = try type()
        let selection = Task { await model.select(type: voice) }
        defer { selection.cancel() }
        await fulfillment(of: [slow.arrived], timeout: 5)
        let chosen = try XCTUnwrap(model.sources.first { $0.id == 20 })
        rig.api.enqueue("/episode/71/1/20", json: episodes("New"))
        await model.select(source: chosen)
        let episode = try XCTUnwrap(model.episodes.first)
        rig.api.enqueue("/episode/watch/71/20/1", json: #"{"code":0}"#)
        await model.markWatched(episode, watched: true)
        slow.respond(episodes("A"))
        await selection.value
        XCTAssertEqual(model.selectedSource?.id, 20)
        XCTAssertEqual(model.episodes.first?.name, "New1")
        XCTAssertEqual(model.episodes.first?.isWatched, true)
        XCTAssertEqual(model.episodesBySource[20]?.first?.name, "New1")
        XCTAssertEqual(model.episodesBySource[20]?.first?.isWatched, true)
    }

    @MainActor
    func testFailedPrefetchIsNotCachedAsAnEmptyListAndSelectionRetries() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let model = try makeModel(rig)
        rig.api.enqueue("/episode/71/1", json: #"{"code":0,"sources":[{"id":10},{"id":20}]}"#)
        rig.api.enqueue("/episode/71/1/10", json: episodes("A"))
        rig.api.enqueue("/episode/71/1/20", json: #"{"code":2}"#)
        try await model.select(type: type())
        XCTAssertNil(model.episodesBySource[20])
        rig.api.enqueue("/episode/71/1/20", json: episodes("Retried"))
        try await model.select(source: XCTUnwrap(model.sources.first { $0.id == 20 }))
        XCTAssertEqual(model.episodes.first?.name, "Retried1")
        XCTAssertEqual(rig.api.requests(to: "/episode/71/1/20").count, 2)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testLateVoiceResponseCannotStopLoadingOrReplaceNewVoice() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let model = try makeModel(rig)
        let oldSource = rig.api.hold("/episode/71/1")
        defer { oldSource.respond("{}", status: 500) }
        let oldType = try type(1)
        let old = Task { await model.select(type: oldType) }
        defer { old.cancel() }
        await fulfillment(of: [oldSource.arrived], timeout: 5)
        rig.api.enqueue("/episode/71/2", json: #"{"code":0,"sources":[{"id":20}]}"#)
        let newEpisodes = rig.api.hold("/episode/71/2/20")
        defer { newEpisodes.respond("{}", status: 500) }
        let newType = try type(2)
        let current = Task { await model.select(type: newType) }
        defer { current.cancel() }
        await fulfillment(of: [newEpisodes.arrived], timeout: 5)
        oldSource.respond(#"{"code":0,"sources":[{"id":10}]}"#)
        await old.value
        XCTAssertTrue(model.isLoadingEpisodes)
        XCTAssertEqual(model.selectedType?.id, 2)
        XCTAssertEqual(model.sources.map(\.id), [20])
        newEpisodes.respond(episodes("New"))
        await current.value
        XCTAssertEqual(model.episodes.first?.name, "New1")
        XCTAssertFalse(model.isLoadingEpisodes)
    }

    @MainActor
    func testRapidHostingSwitchIgnoresOlderDirectEpisodeLoad() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let model = try await readyModel(rig)
        let first = rig.api.hold("/episode/71/1/10")
        defer { first.respond("{}", status: 500) }
        let old = Task { await model.loadEpisodes() }
        defer { old.cancel() }
        await fulfillment(of: [first.arrived], timeout: 5)
        try await model.select(source: XCTUnwrap(model.sources.first { $0.id == 20 }))
        first.respond(episodes("Stale"))
        await old.value
        XCTAssertEqual(model.selectedSource?.id, 20)
        XCTAssertEqual(model.episodes.first?.name, "B1")
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testEpisodeLoadCannotEraseMarkAcknowledgedAfterLoadStarted() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = try await readyModel(rig)
        let original = try XCTUnwrap(model.episodes.first)
        let list = rig.api.hold("/episode/71/1/10")
        defer { list.respond("{}", status: 500) }
        let reload = Task { await model.loadEpisodes() }
        defer { reload.cancel() }
        await fulfillment(of: [list.arrived], timeout: 5)
        let mark = rig.api.hold("/episode/watch/71/10/1")
        defer { mark.respond("{}", status: 500) }
        let watch = Task { await model.markWatched(original, watched: true) }
        defer { watch.cancel() }
        await fulfillment(of: [mark.arrived], timeout: 5)
        XCTAssertEqual(model.episodes.first?.isWatched, true)
        mark.respond(#"{"code":0}"#)
        await watch.value
        list.respond(episodes("A", watched: false))
        await reload.value
        XCTAssertEqual(model.episodes.first?.isWatched, true)
        XCTAssertEqual(model.episodesBySource[10]?.first?.isWatched, true)
        // A later request is allowed to adopt fresh server truth rather than
        // retaining a permanent optimistic override.
        rig.api.enqueue("/episode/71/1/10", json: episodes("Fresh", watched: false))
        await model.loadEpisodes()
        XCTAssertEqual(model.episodes.first?.isWatched, false)
    }

    @MainActor
    func testEpisodeLoadDuringPendingWatchKeepsOptimisticMark() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = try await readyModel(rig)
        let episode = try XCTUnwrap(model.episodes.first)
        let mark = rig.api.hold("/episode/watch/71/10/1")
        defer { mark.respond("{}", status: 500) }
        let watch = Task { await model.markWatched(episode, watched: true) }
        defer { watch.cancel() }
        await fulfillment(of: [mark.arrived], timeout: 5)
        rig.api.enqueue("/episode/71/1/10", json: episodes("A", watched: false))
        await model.loadEpisodes()
        XCTAssertEqual(model.episodes.first?.isWatched, true)
        mark.respond(#"{"code":2}"#)
        await watch.value
        XCTAssertEqual(model.episodes.first?.isWatched, false)
        XCTAssertNotNil(model.errorMessage)
    }

    @MainActor
    func testUnconfirmedWatchActionsRollbackWithoutRefreshingProfile() async throws {
        for watched in [true, false] {
            for json in ["{}", #"{"code":null}"#, #"{"code":2}"#] {
                let rig = ProfileTestRig()
                try await rig.signIn()
                let model = try await readyModel(rig, watched: !watched)
                let episode = try XCTUnwrap(model.episodes.first)
                let path = watched ? "/episode/watch/71/10/1" : "/episode/unwatch/71/10/1"
                let refreshes = rig.api.requests(to: "/profile/42").count
                rig.api.enqueue(path, json: json)
                await model.markWatched(episode, watched: watched)
                XCTAssertEqual(model.episodes.first?.isWatched, !watched)
                XCTAssertEqual(model.episodesBySource[10]?.first?.isWatched, !watched)
                XCTAssertEqual(model.episodesBySource[20]?.first?.isWatched, !watched)
                XCTAssertNotNil(model.errorMessage)
                XCTAssertFalse(model.isUpdatingWatched)
                XCTAssertEqual(rig.api.requests(to: path).count, 1)
                XCTAssertEqual(rig.api.requests(to: "/profile/42").count, refreshes)

                rig.api.enqueue(path, json: #"{"code":0}"#)
                await model.markWatched(episode, watched: watched)
                XCTAssertEqual(model.episodes.first?.isWatched, watched)
                XCTAssertEqual(model.episodesBySource[10]?.first?.isWatched, watched)
                XCTAssertFalse(model.isUpdatingWatched)
                XCTAssertEqual(rig.api.requests(to: "/profile/42").count, refreshes + 1)
            }
        }
    }

    @MainActor
    func testUnconfirmedBulkActionsKeepCacheWithoutReloadingEpisodesOrProfile() async throws {
        for watched in [true, false] {
            for json in ["{}", #"{"code":null}"#, #"{"code":2}"#] {
                let rig = ProfileTestRig()
                try await rig.signIn()
                let model = try await readyModel(rig, watched: !watched)
                let path = watched ? "/episode/watch/71/10" : "/episode/unwatch/71/10"
                let episodeLoads = rig.api.requests(to: "/episode/71/1/10").count
                let refreshes = rig.api.requests(to: "/profile/42").count
                rig.api.enqueue(path, json: json)
                if watched { await model.markAllWatched() } else { await model.markAllUnwatched() }
                XCTAssertEqual(model.episodes.first?.name, "A1")
                XCTAssertEqual(model.episodes.first?.isWatched, !watched)
                XCTAssertEqual(model.episodesBySource[10]?.first?.isWatched, !watched)
                XCTAssertNotNil(model.errorMessage)
                XCTAssertFalse(model.isUpdatingWatched)
                XCTAssertEqual(rig.api.requests(to: path).count, 1)
                XCTAssertEqual(rig.api.requests(to: "/episode/71/1/10").count, episodeLoads)
                XCTAssertEqual(rig.api.requests(to: "/profile/42").count, refreshes)

                rig.api.enqueue(path, json: #"{"code":0}"#)
                rig.api.enqueue("/episode/71/1/10", json: episodes("Confirmed", watched: watched))
                if watched { await model.markAllWatched() } else { await model.markAllUnwatched() }
                XCTAssertEqual(model.episodes.first?.name, "Confirmed1")
                XCTAssertEqual(model.episodes.first?.isWatched, watched)
                XCTAssertEqual(model.episodesBySource[10]?.first?.isWatched, watched)
                XCTAssertEqual(model.episodesBySource[20]?.first?.isWatched, !watched)
                XCTAssertNil(model.errorMessage)
                XCTAssertFalse(model.isUpdatingWatched)
                XCTAssertEqual(rig.api.requests(to: "/episode/71/1/10").count, episodeLoads + 1)
                XCTAssertEqual(rig.api.requests(to: "/profile/42").count, refreshes + 1)
            }
        }
    }

    @MainActor
    func testCancelledWatchActionsRollbackWithoutErrorOrProfileRefresh() async throws {
        for watched in [true, false] {
            let rig = ProfileTestRig()
            try await rig.signIn()
            let model = try await readyModel(rig, watched: !watched)
            let episode = try XCTUnwrap(model.episodes.first)
            let path = watched ? "/episode/watch/71/10/1" : "/episode/unwatch/71/10/1"
            let held = rig.api.hold(path)
            defer { held.respond("{}", status: 500) }
            let mutation = Task { await model.markWatched(episode, watched: watched) }
            defer { mutation.cancel() }
            await fulfillment(of: [held.arrived], timeout: 5)
            XCTAssertEqual(model.episodes.first?.isWatched, watched)
            mutation.cancel()
            await mutation.value
            await fulfillment(of: [held.cancelled], timeout: 5)
            XCTAssertEqual(model.episodes.first?.isWatched, !watched)
            XCTAssertEqual(model.episodesBySource[10]?.first?.isWatched, !watched)
            XCTAssertNil(model.errorMessage)
            XCTAssertFalse(model.isUpdatingWatched)
            XCTAssertTrue(rig.api.requests(to: "/profile/42").isEmpty)
        }
    }

    @MainActor
    func testProgressFailuresRemainBestEffortWithoutChangingMarksOrRefreshingProfile() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = try await readyModel(rig)
        let episode = try XCTUnwrap(model.episodes.first)
        let path = "/history/add/71/10/1"
        for json in ["{}", #"{"code":null}"#, #"{"code":2}"#, #"{"code":0}"#] {
            rig.api.enqueue(path, json: json)
            await model.saveProgress(for: episode, seconds: 123)
            XCTAssertEqual(model.episodes.first?.isWatched, false)
            XCTAssertEqual(model.episodesBySource[10]?.first?.isWatched, false)
            XCTAssertNil(model.errorMessage)
            XCTAssertFalse(model.isUpdatingWatched)
            XCTAssertTrue(rig.api.requests(to: "/profile/42").isEmpty)
        }
        XCTAssertEqual(rig.api.requests(to: path).count, 4)
    }

    @MainActor
    func testLateWatchFailureRollsBackOriginalHostingWithoutErrorInNewHosting() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = try await readyModel(rig)
        let episode = try XCTUnwrap(model.episodes.first)
        let held = rig.api.hold("/episode/watch/71/10/1")
        defer { held.respond("{}", status: 500) }
        let watch = Task { await model.markWatched(episode, watched: true) }
        defer { watch.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        try await model.select(source: XCTUnwrap(model.sources.first { $0.id == 20 }))
        held.respond(#"{"code":2}"#)
        await watch.value
        XCTAssertEqual(model.episodes.first?.name, "B1")
        XCTAssertEqual(model.episodesBySource[10]?.first?.isWatched, false)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testWatchFailureCannotRollbackReopenedSameVoiceGeneration() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = try await readyModel(rig)
        let episode = try XCTUnwrap(model.episodes.first)
        let held = rig.api.hold("/episode/watch/71/10/1")
        defer { held.respond("{}", status: 500) }
        let watch = Task { await model.markWatched(episode, watched: true) }
        defer { watch.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        rig.api.enqueue("/episode/71/1", json: #"{"code":0,"sources":[{"id":10}]}"#)
        rig.api.enqueue("/episode/71/1/10", json: episodes("Reopened", watched: true))
        try await model.select(type: type())
        held.respond(#"{"code":2}"#)
        await watch.value
        XCTAssertEqual(model.episodes.first?.name, "Reopened1")
        XCTAssertEqual(model.episodes.first?.isWatched, true)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testBulkResponseCannotInvalidateReopenedSameVoiceGeneration() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = try await readyModel(rig)
        let held = rig.api.hold("/episode/watch/71/10")
        defer { held.respond("{}", status: 500) }
        let bulk = Task { await model.markAllWatched() }
        defer { bulk.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        rig.api.enqueue("/episode/71/1", json: #"{"code":0,"sources":[{"id":10}]}"#)
        rig.api.enqueue("/episode/71/1/10", json: episodes("Reopened", watched: true))
        try await model.select(type: type())
        held.respond(#"{"code":0}"#)
        await bulk.value
        XCTAssertEqual(model.episodes.first?.name, "Reopened1")
        XCTAssertEqual(model.episodesBySource[10]?.first?.isWatched, true)
        XCTAssertEqual(rig.api.requests(to: "/episode/71/1/10").count, 2)
    }

    @MainActor
    func testBulkInvalidationCannotBeUndoneByEarlierPrefetch() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = try makeModel(rig)
        rig.api.enqueue("/episode/71/1", json: #"{"code":0,"sources":[{"id":10},{"id":20}]}"#)
        let prefetchA = rig.api.hold("/episode/71/1/10")
        let prefetchB = rig.api.hold("/episode/71/1/20")
        defer { prefetchA.respond("{}", status: 500); prefetchB.respond("{}", status: 500) }
        let voice = try type()
        let selection = Task { await model.select(type: voice) }
        defer { selection.cancel() }
        await fulfillment(of: [prefetchA.arrived, prefetchB.arrived], timeout: 5)
        rig.api.enqueue("/episode/71/1/10", json: episodes("A"))
        try await model.select(source: XCTUnwrap(model.sources.first { $0.id == 10 }))
        let held = rig.api.hold("/episode/watch/71/10")
        defer { held.respond("{}", status: 500) }
        let bulk = Task { await model.markAllWatched() }
        defer { bulk.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        rig.api.enqueue("/episode/71/1/20", json: episodes("B"))
        try await model.select(source: XCTUnwrap(model.sources.first { $0.id == 20 }))
        held.respond(#"{"code":0}"#)
        await bulk.value
        prefetchA.respond(episodes("OldA"))
        prefetchB.respond(episodes("OldB"))
        await selection.value
        XCTAssertNil(model.episodesBySource[10])
        XCTAssertEqual(model.selectedSource?.id, 20)
        rig.api.enqueue("/episode/71/1/10", json: episodes("ConfirmedA", watched: true))
        try await model.select(source: XCTUnwrap(model.sources.first { $0.id == 10 }))
        XCTAssertEqual(model.episodes.first?.name, "ConfirmedA1")
        XCTAssertEqual(model.episodes.first?.isWatched, true)
    }

    @MainActor
    func testPlaybackProgressAndNextEpisodeKeepOriginalHostingAfterSwitch() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = try await readyModel(rig)
        let original = try XCTUnwrap(model.episodes.first)
        try await model.select(source: XCTUnwrap(model.sources.first { $0.id == 20 }))
        XCTAssertEqual(model.nextEpisode(after: original)?.name, "A2")
        XCTAssertEqual(model.nextEpisode(after: original)?.sourceId, 10)
        rig.api.enqueue("/history/add/71/10/1", json: #"{"code":0}"#)
        await model.saveProgress(for: original, seconds: 123)
        XCTAssertEqual(rig.api.requests(to: "/history/add/71/10/1").count, 1)
        XCTAssertTrue(rig.api.requests(to: "/history/add/71/20/1").isEmpty)
    }

    @MainActor
    func testNewLoginBlocksOldEpisodeActionsAndClearsOldDataOnInvalidation() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "first")
        let model = try await readyModel(rig)
        let episode = try XCTUnwrap(model.episodes.first)
        try await rig.signIn(token: "second")
        model.invalidate()
        let before = rig.api.requests.count
        await model.markWatched(episode, watched: true)
        await model.markAllWatched()
        await model.saveProgress(for: episode, seconds: 10)
        XCTAssertEqual(rig.api.requests.count, before)
        XCTAssertNil(model.nextEpisode(after: episode))
        XCTAssertTrue(model.episodes.isEmpty)
        XCTAssertFalse(model.hasCurrentViewer)
    }

    @MainActor
    func testReloadCancelsOldPlayabilityTaskWithoutPublishingItsResults() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let model = try makeModel(rig)
        defer { model.invalidate() }
        rig.api.enqueue("/episode/71", json: #"{"code":0,"types":[{"id":1}]}"#)
        let sources = rig.api.hold("/episode/71/1")
        defer { sources.respond("{}", status: 500) }
        await model.loadTypes()
        await fulfillment(of: [sources.arrived], timeout: 5)
        XCTAssertTrue(model.isCheckingPlayability)
        rig.api.enqueue("/episode/71", json: #"{"code":0,"types":[]}"#)
        await model.reload()
        await fulfillment(of: [sources.cancelled], timeout: 5)
        XCTAssertTrue(model.playableTypeIDs.isEmpty)
        XCTAssertTrue(model.types.isEmpty)
        XCTAssertNil(model.errorMessage)
        model.invalidate()
        XCTAssertFalse(model.isCheckingPlayability)
    }
}
