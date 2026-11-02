import Foundation
import SwiftUI
import XCTest
import AnixartKit
@testable import Anixart

final class VoiceSearchScopeTests: XCTestCase {
    @MainActor
    func testFinalTextUsesExistingScopedV2SearchAndKeepsAppliedFilter() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let service = VoiceTestService()
        let filter = FilterRequest(country: "Китай", source: .manga)
        let catalog = CatalogViewModel(session: rig.session, filter: filter, searchScope: .titleOriginal,
                                       hasAppliedFilter: true, voiceServiceFactory: { service })
        let browse = catalog.browse
        catalog.setVoiceSearchActive(true)
        catalog.beginVoiceSearch()
        let input = try XCTUnwrap(catalog.voiceInput)
        await fulfillment(of: [service.started], timeout: 5)
        service.emit(.transcript(" Naruto ", isFinal: false))
        XCTAssertEqual(catalog.query, "")
        XCTAssertTrue(rig.api.requests.isEmpty)
        service.emit(.transcript(" Naruto ", isFinal: true))
        XCTAssertEqual(catalog.query, "Naruto")
        XCTAssertEqual(catalog.searchScope, .titleOriginal)
        XCTAssertTrue(catalog.hasAppliedFilter)
        XCTAssertEqual(catalog.filter, filter)
        XCTAssertTrue(catalog.browse === browse)
        XCTAssertNil(catalog.voiceInput)
        XCTAssertEqual(input.state, .completed)
        XCTAssertFalse(service.isListening)
        rig.api.enqueue("/search/releases/0", json: #"{"code":0,"releases":[{"id":71}]}"#)
        await catalog.search()
        let request = try XCTUnwrap(rig.api.requests.first)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(request.url?.path, "/search/releases/0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "API-Version"), "v2")
        XCTAssertEqual(body["query"] as? String, "Naruto")
        XCTAssertEqual(body["searchBy"] as? Int, 2)
        XCTAssertNil(body["source"])
        XCTAssertNil(body["country"])
        XCTAssertFalse(request.url?.query?.contains("token") == true)
    }

    @MainActor
    func testManualQueryChangeStopsVoiceAndLateCallbacksCannotOverwriteIt() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let service = VoiceTestService()
        let catalog = CatalogViewModel(session: rig.session, voiceServiceFactory: { service })
        catalog.setVoiceSearchActive(true)
        catalog.beginVoiceSearch()
        let input = try XCTUnwrap(catalog.voiceInput)
        await fulfillment(of: [service.started], timeout: 5)
        catalog.query = "Мой ручной запрос"
        XCTAssertNil(catalog.voiceInput)
        XCTAssertFalse(service.isListening)
        service.emit(.transcript("Late voice", isFinal: true))
        XCTAssertEqual(catalog.query, "Мой ручной запрос")
        XCTAssertEqual(input.state, .cancelled)
        XCTAssertTrue(rig.api.requests.isEmpty)
    }

    @MainActor
    func testManualQueryABACannotRestoreAnOlderVoiceContext() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let service = VoiceTestService()
        let catalog = CatalogViewModel(session: rig.session, voiceServiceFactory: { service })
        catalog.setVoiceSearchActive(true)
        catalog.beginVoiceSearch()
        let input = try XCTUnwrap(catalog.voiceInput)
        await fulfillment(of: [service.started], timeout: 5)
        catalog.query = "Changed"
        catalog.query = ""
        service.emit(.transcript("Older request", isFinal: true))
        XCTAssertEqual(catalog.query, "")
        XCTAssertEqual(input.state, .cancelled)
        XCTAssertNil(catalog.voiceInput)
    }

    @MainActor
    func testScopeSwitchAndExplicitSameFilterApplyRetireVoice() async throws {
        for applyFilter in [false, true] {
            let rig = ProfileTestRig()
            await rig.session.restore()
            let service = VoiceTestService()
            let filter = FilterRequest(source: .manga)
            let catalog = CatalogViewModel(session: rig.session, filter: filter, voiceServiceFactory: { service })
            catalog.setVoiceSearchActive(true)
            catalog.beginVoiceSearch()
            let input = try XCTUnwrap(catalog.voiceInput)
            await fulfillment(of: [service.started], timeout: 5)
            if applyFilter { catalog.apply(filter: filter) }
            else { catalog.searchScope = .titleAlt }
            service.emit(.transcript("Late", isFinal: true))
            XCTAssertEqual(catalog.query, "")
            XCTAssertNil(catalog.voiceInput)
            XCTAssertEqual(input.state, .cancelled)
            XCTAssertFalse(service.isListening)
            XCTAssertEqual(catalog.filter, filter)
            XCTAssertTrue(rig.api.requests.isEmpty)
        }
    }

    @MainActor
    func testSceneInactivationOrDisappearanceStopsInputWithoutAutoRestart() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let service = VoiceTestService()
        let catalog = CatalogViewModel(session: rig.session, voiceServiceFactory: { service })
        catalog.setVoiceSearchActive(true)
        catalog.beginVoiceSearch()
        let input = try XCTUnwrap(catalog.voiceInput)
        await fulfillment(of: [service.started], timeout: 5)
        catalog.setVoiceSearchActive(false) // The same hook is used by scenePhase and onDisappear.
        service.emit(.transcript("Late", isFinal: true))
        XCTAssertEqual(input.state, .cancelled)
        XCTAssertFalse(service.isListening)
        catalog.setVoiceSearchActive(true)
        XCTAssertNil(catalog.voiceInput)
        XCTAssertEqual(service.starts, 1)
        XCTAssertEqual(catalog.query, "")
    }

    @MainActor
    func testInactiveNonemptyAndStaleSearchCannotCreateVoiceService() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        var creations = 0
        let service = VoiceTestService()
        let catalog = CatalogViewModel(session: rig.session, voiceServiceFactory: { creations += 1; return service })
        catalog.beginVoiceSearch()
        catalog.setVoiceSearchActive(true)
        catalog.query = "Manual"
        catalog.beginVoiceSearch()
        catalog.query = " \n "
        catalog.beginVoiceSearch()
        catalog.query = ""
        try await rig.signIn()
        catalog.beginVoiceSearch()
        XCTAssertEqual(creations, 0)
        XCTAssertNil(catalog.voiceInput)
        XCTAssertTrue(service.permissionRequests.isEmpty)
        XCTAssertEqual(service.starts, 0)
    }

    @MainActor
    func testViewerChangeDuringPermissionNeverStartsOrUsesNewAccount() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let viewer = rig.session.viewerKey
        let service = VoiceTestService()
        service.speechAuthorization = .notDetermined
        service.microphoneAuthorization = .notDetermined
        let gate = ProfileTestGate()
        service.speechGate = gate
        var query = "Manual"
        let input = VoiceSearchModel(service: service, isContextCurrent: { viewer == rig.session.viewerKey }, onText: { query = $0 })
        let starting = Task { await input.start() }
        defer { gate.release(); starting.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        try await rig.signIn()
        gate.release()
        await starting.value
        XCTAssertEqual(input.state, .cancelled)
        XCTAssertEqual(service.permissionRequests, [.speech])
        XCTAssertEqual(service.starts, 0)
        XCTAssertEqual(query, "Manual")
    }

    @MainActor
    func testSameProfileNewSessionStopsListeningWithoutWaitingForOSCallbackOrViewHook() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "first")
        let viewer = rig.session.viewerKey
        let service = VoiceTestService()
        var query = "Manual"
        let stopped = XCTestExpectation(description: "Viewer change stopped mock recording")
        service.onStopped = { stopped.fulfill() }
        let input = VoiceSearchModel(service: service, isContextCurrent: { viewer == rig.session.viewerKey }, onText: { query = $0 })
        await input.start()
        try await rig.signIn(token: "second")
        await fulfillment(of: [stopped], timeout: 5)
        XCTAssertEqual(input.state, .cancelled)
        XCTAssertFalse(service.isListening)
        service.emit(.transcript("Late old-account text", isFinal: true))
        XCTAssertEqual(query, "Manual")
        XCTAssertEqual(rig.session.viewerKey.account?.profileID, 42)
        XCTAssertNotEqual(rig.session.viewerKey, viewer)
    }

    @MainActor
    func testOldSheetDismissAndRetryCannotStopANewerVoicePresentation() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let first = VoiceTestService()
        let second = VoiceTestService()
        var services = [first, second]
        let catalog = CatalogViewModel(session: rig.session, voiceServiceFactory: { services.removeFirst() })
        catalog.setVoiceSearchActive(true)
        catalog.beginVoiceSearch()
        let old = try XCTUnwrap(catalog.voiceInput)
        await fulfillment(of: [first.started], timeout: 5)
        catalog.closeVoiceSearch()
        catalog.beginVoiceSearch()
        let current = try XCTUnwrap(catalog.voiceInput)
        await fulfillment(of: [second.started], timeout: 5)
        catalog.closeVoiceSearch(ifCurrent: old)
        catalog.retryVoiceSearch(ifCurrent: old)
        XCTAssertTrue(catalog.voiceInput === current)
        XCTAssertEqual(current.state, .listening)
        XCTAssertTrue(second.isListening)
        XCTAssertEqual(second.starts, 1)
        first.emit(.transcript("Old", isFinal: true))
        XCTAssertEqual(catalog.query, "")
        catalog.closeVoiceSearch()
    }

    @MainActor
    func testVoiceCancelAndFinalResultNeverRewriteHomePreferences() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let suite = "VoiceSearchScopeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = HomePreferences(defaults: defaults)
        preferences.setDefaultTab(.movies)
        var custom = CustomTabFilter()
        custom.country = "Китай"
        custom.genres = ["драма"]
        preferences.save(customFilter: custom)
        let stored = defaults.persistentDomain(forName: suite) as NSDictionary?
        let service = VoiceTestService()
        let catalog = CatalogViewModel(session: rig.session, filter: FilterRequest(studio: "OLM"), voiceServiceFactory: { service })
        catalog.setVoiceSearchActive(true)
        catalog.beginVoiceSearch()
        await fulfillment(of: [service.started], timeout: 5)
        catalog.setVoiceSearchActive(true) // Repeated active notifications are a no-op.
        XCTAssertTrue(service.isListening)
        service.emit(.transcript("Наруто", isFinal: true))
        XCTAssertEqual(catalog.query, "Наруто")
        XCTAssertEqual(catalog.filter.studio, "OLM")
        XCTAssertEqual(defaults.persistentDomain(forName: suite) as NSDictionary?, stored)
        XCTAssertEqual(HomePreferences(defaults: defaults).customFilter, custom)
        XCTAssertEqual(HomePreferences(defaults: defaults).defaultTab, .movies)
        XCTAssertTrue(rig.api.requests.isEmpty)
    }

    @MainActor
    func testOldSheetBindingDismissalCannotCancelNewPresentation() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let first = VoiceTestService()
        let second = VoiceTestService()
        var services = [first, second]
        let catalog = CatalogViewModel(session: rig.session, voiceServiceFactory: { services.removeFirst() })
        catalog.setVoiceSearchActive(true)
        catalog.beginVoiceSearch()
        let old = voiceSearchPresentationBinding(catalog)
        await fulfillment(of: [first.started], timeout: 5)
        catalog.closeVoiceSearch()
        catalog.beginVoiceSearch()
        let current = try XCTUnwrap(catalog.voiceInput)
        await fulfillment(of: [second.started], timeout: 5)
        old.wrappedValue = false
        XCTAssertTrue(catalog.voiceInput === current)
        XCTAssertTrue(second.isListening)
        XCTAssertFalse(old.wrappedValue)
        let currentPresentation = voiceSearchPresentationBinding(catalog)
        currentPresentation.wrappedValue = false
        XCTAssertFalse(second.isListening)
        XCTAssertNil(catalog.voiceInput)
    }
}
