import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class ReleaseSearchHistoryTests: XCTestCase {
    private func storage() throws -> UserDefaults {
        let suite = "ReleaseSearchHistoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    @MainActor
    func testEmptyHistoryDoesNotWritePreferences() throws {
        let defaults = try storage()
        let history = ReleaseSearchHistoryStore(profileID: 42, defaults: defaults)
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertNil(defaults.data(forKey: "search.release.history.42"))
    }

    @MainActor
    func testExplicitQueriesPersistNormalizeWhitespaceAndDeduplicateByScope() throws {
        let defaults = try storage()
        let history = ReleaseSearchHistoryStore(profileID: 42, defaults: defaults)
        history.remember(query: "  Naruto \n", scope: .all)
        history.remember(query: "One   Piece", scope: .all)
        history.remember(query: "NARUTO", scope: .all)
        history.remember(query: "Naruto", scope: .titleOriginal)
        XCTAssertEqual(history.entries.map(\.query), ["Naruto", "NARUTO", "One Piece"])
        XCTAssertEqual(history.entries.map(\.scope), [.titleOriginal, .all, .all])
        XCTAssertEqual(ReleaseSearchHistoryStore(profileID: 42, defaults: defaults).entries, history.entries)
        let data = try XCTUnwrap(defaults.data(forKey: "search.release.history.42"))
        let stored = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertTrue(stored.allSatisfy { Set($0.keys) == Set(["query", "scope", "usedAt"]) })
    }

    @MainActor
    func testHistoryHasABoundedNewestFirstWindow() throws {
        let history = ReleaseSearchHistoryStore(profileID: 42, defaults: try storage())
        for index in 0..<30 { history.remember(query: "Query \(index)", scope: .all) }
        XCTAssertEqual(history.entries.count, 20)
        XCTAssertEqual(history.entries.first?.query, "Query 29")
        XCTAssertEqual(history.entries.last?.query, "Query 10")
    }

    @MainActor
    func testGuestAndDifferentAccountsNeverShareVisibleHistory() throws {
        let defaults = try storage()
        let owner = ReleaseSearchHistoryStore(profileID: 42, defaults: defaults)
        owner.remember(query: "Owner", scope: .all)
        let other = ReleaseSearchHistoryStore(profileID: 43, defaults: defaults)
        other.remember(query: "Other", scope: .all)
        let guest = ReleaseSearchHistoryStore(profileID: nil, defaults: defaults)
        XCTAssertTrue(guest.entries.isEmpty)
        guest.remember(query: "Guest", scope: .all)
        XCTAssertEqual(ReleaseSearchHistoryStore(profileID: 42, defaults: defaults).entries.map(\.query), ["Owner"])
        XCTAssertEqual(ReleaseSearchHistoryStore(profileID: 43, defaults: defaults).entries.map(\.query), ["Other"])
        XCTAssertEqual(ReleaseSearchHistoryStore(profileID: nil, defaults: defaults).entries.map(\.query), ["Guest"])
    }

    @MainActor
    func testRemovalAndClearOnlyAffectThisProfile() throws {
        let defaults = try storage()
        let owner = ReleaseSearchHistoryStore(profileID: 42, defaults: defaults)
        let other = ReleaseSearchHistoryStore(profileID: 43, defaults: defaults)
        owner.remember(query: "One", scope: .all)
        owner.remember(query: "Two", scope: .all)
        other.remember(query: "Other", scope: .all)
        owner.remove(id: try XCTUnwrap(owner.entries.first?.id))
        XCTAssertEqual(owner.entries.map(\.query), ["One"])
        owner.clear()
        XCTAssertNil(defaults.data(forKey: "search.release.history.42"))
        XCTAssertEqual(ReleaseSearchHistoryStore(profileID: 43, defaults: defaults).entries.map(\.query), ["Other"])
    }

    @MainActor
    func testTwoSnapshotsMergeAndDoNotResurrectAClearedHistory() throws {
        let defaults = try storage()
        let first = ReleaseSearchHistoryStore(profileID: 42, defaults: defaults)
        let second = ReleaseSearchHistoryStore(profileID: 42, defaults: defaults)
        first.remember(query: "One", scope: .all)
        second.remember(query: "Two", scope: .all)
        XCTAssertEqual(second.entries.map(\.query), ["Two", "One"])
        XCTAssertTrue(first.remove(id: try XCTUnwrap(first.entries.first?.id)))
        XCTAssertEqual(first.entries.map(\.query), ["Two"])
        first.clear()
        second.remember(query: "Three", scope: .all)
        XCTAssertEqual(second.entries.map(\.query), ["Three"])
        XCTAssertFalse(first.remove(id: "missing"))
        XCTAssertEqual(first.entries.map(\.query), ["Three"])
    }

    @MainActor
    func testBlankOversizedAndNonTitleSearchesAreNotStored() throws {
        let history = ReleaseSearchHistoryStore(profileID: 42, defaults: try storage())
        history.remember(query: " \n ", scope: .all)
        history.remember(query: String(repeating: "x", count: 301), scope: .all)
        history.remember(query: "Манга", scope: .sourceMaterial)
        XCTAssertTrue(history.entries.isEmpty)
    }

    @MainActor
    func testMalformedStoredHistoryDoesNotBecomeFakeEntriesOrRewriteData() throws {
        let defaults = try storage()
        let data = Data("not json".utf8)
        defaults.set(data, forKey: "search.release.history.42")
        XCTAssertTrue(ReleaseSearchHistoryStore(profileID: 42, defaults: defaults).entries.isEmpty)
        XCTAssertEqual(defaults.data(forKey: "search.release.history.42"), data)
    }

    @MainActor
    func testAutomaticSearchDoesNotStorePrefixesButExplicitUseDoes() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let history = ReleaseSearchHistoryStore(profileID: nil, defaults: try storage())
        let model = CatalogViewModel(session: rig.session, query: "Naruto", history: history)
        rig.api.enqueue("/search/releases/0", json: #"{"code":0,"releases":[{"id":71}]}"#)
        await model.search()
        XCTAssertTrue(history.entries.isEmpty)
        model.rememberSearch()
        XCTAssertEqual(history.entries.map(\.query), ["Naruto"])
        model.query = ""
        model.useHistory(try XCTUnwrap(history.entries.first))
        XCTAssertEqual(model.query, "Naruto")
        XCTAssertEqual(model.searchScope, .all)
        XCTAssertTrue(model.removeHistoryEntry(id: try XCTUnwrap(history.entries.first?.id)))
        XCTAssertTrue(history.entries.isEmpty)
        model.rememberSearch()
        XCTAssertTrue(model.clearHistory())
        XCTAssertFalse(model.clearHistory())
    }

    @MainActor
    func testRetiredViewerCannotAppendOrUseHistoryWithANewerSession() async throws {
        for nextProfileID in [42, 43] {
            let rig = ProfileTestRig()
            try await rig.signIn(profileID: 42, token: "first")
            let history = ReleaseSearchHistoryStore(profileID: 42, defaults: try storage())
            let model = CatalogViewModel(session: rig.session, query: "Old", history: history)
            history.remember(query: "Saved", scope: .all)
            let saved = try XCTUnwrap(history.entries.first)
            try await rig.signIn(profileID: nextProfileID, token: "second")
            model.rememberSearch()
            model.useHistory(saved)
            XCTAssertFalse(model.removeHistoryEntry(id: saved.id))
            XCTAssertFalse(model.clearHistory())
            XCTAssertEqual(history.entries.map(\.query), ["Saved"])
            XCTAssertEqual(model.query, "Old")
        }
    }

    @MainActor
    func testWrongHistoryOwnerOrNoHistoryCannotUseOrMutateStoredQueries() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(profileID: 42)
        let defaults = try storage()
        let other = ReleaseSearchHistoryStore(profileID: 43, defaults: defaults)
        other.remember(query: "Other account", scope: .all)
        let saved = try XCTUnwrap(other.entries.first)
        for history in [other, nil] {
            let model = CatalogViewModel(session: rig.session, query: "Current", history: history)
            model.rememberSearch()
            model.useHistory(saved)
            XCTAssertFalse(model.removeHistoryEntry(id: saved.id))
            XCTAssertFalse(model.clearHistory())
            XCTAssertEqual(model.query, "Current")
        }
        XCTAssertEqual(other.entries.map(\.query), ["Other account"])
        XCTAssertNil(defaults.data(forKey: "search.release.history.42"))
    }

    @MainActor
    func testAcceptedVoiceInputStoresOnlyTheFinalChosenQuery() async throws {
        for usesFind in [false, true] {
            let rig = ProfileTestRig()
            await rig.session.restore()
            let service = VoiceTestService()
            let history = ReleaseSearchHistoryStore(profileID: nil, defaults: try storage())
            let model = CatalogViewModel(session: rig.session, searchScope: .titleOriginal,
                                         history: history, voiceServiceFactory: { service })
            model.setVoiceSearchActive(true)
            model.beginVoiceSearch()
            let input = try XCTUnwrap(model.voiceInput)
            await fulfillment(of: [service.started], timeout: 5)
            service.emit(.transcript(" Na ", isFinal: false))
            XCTAssertTrue(history.entries.isEmpty)
            service.emit(.transcript(" Naruto ", isFinal: !usesFind))
            if usesFind { input.useTranscript() }
            service.emit(.transcript("Late", isFinal: true))
            XCTAssertEqual(history.entries.map(\.query), ["Naruto"])
            XCTAssertEqual(history.entries.map(\.scope), [.titleOriginal])
            XCTAssertEqual(model.query, "Naruto")
            XCTAssertNil(model.voiceInput)
            XCTAssertTrue(service.permissionRequests.isEmpty)
            XCTAssertTrue(rig.api.requests.isEmpty)
        }
    }
}
