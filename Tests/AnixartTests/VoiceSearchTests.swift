import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class VoiceSearchTests: XCTestCase {
    @MainActor
    func testConstructionAndAppearanceDoNotCreateServiceOrAskPermission() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let service = VoiceTestService()
        var creations = 0
        let catalog = CatalogViewModel(session: rig.session, voiceServiceFactory: { creations += 1; return service })
        catalog.setVoiceSearchActive(true)
        catalog.setVoiceSearchActive(false)
        XCTAssertEqual(creations, 0)
        XCTAssertTrue(service.permissionRequests.isEmpty)
        XCTAssertEqual(service.starts, 0)
        XCTAssertEqual(service.stops, 0)
        XCTAssertNil(catalog.voiceInput)
        XCTAssertTrue(rig.api.requests.isEmpty)
    }

    @MainActor
    func testAuthorizedExplicitStartListensWithoutPermissionRequests() async {
        let service = VoiceTestService()
        let input = VoiceSearchModel(service: service, isContextCurrent: { true }, onText: { _ in })
        XCTAssertEqual(input.state, .idle)
        await input.start()
        XCTAssertEqual(input.state, .listening)
        XCTAssertTrue(service.isListening)
        XCTAssertEqual(service.starts, 1)
        XCTAssertTrue(service.permissionRequests.isEmpty)
        input.cancel()
    }

    @MainActor
    func testPermissionsAreSequentialAndMicrophoneWaitsForSpeechGrant() async {
        let service = VoiceTestService()
        service.speechAuthorization = .notDetermined
        service.microphoneAuthorization = .notDetermined
        let speech = ProfileTestGate()
        let microphone = ProfileTestGate()
        service.speechGate = speech
        service.microphoneGate = microphone
        let input = VoiceSearchModel(service: service, isContextCurrent: { true }, onText: { _ in })
        let starting = Task { await input.start() }
        defer { speech.release(); microphone.release(); starting.cancel(); input.cancel() }
        await fulfillment(of: [speech.entered], timeout: 5)
        XCTAssertEqual(input.state, .authorizing(.speech))
        XCTAssertEqual(service.permissionRequests, [.speech])
        XCTAssertEqual(service.starts, 0)
        speech.release()
        await fulfillment(of: [microphone.entered], timeout: 5)
        XCTAssertEqual(input.state, .authorizing(.microphone))
        XCTAssertEqual(service.starts, 0)
        microphone.release()
        await starting.value
        XCTAssertEqual(service.permissionRequests, [.speech, .microphone])
        XCTAssertEqual(input.state, .listening)
    }

    @MainActor
    func testDeniedAndRestrictedSpeechNeverRequestMicrophoneOrStartAudio() async {
        for status in [VoicePermissionStatus.denied, .restricted] {
            let service = VoiceTestService()
            service.speechAuthorization = status
            service.microphoneAuthorization = .notDetermined
            let input = VoiceSearchModel(service: service, isContextCurrent: { true }, onText: { _ in XCTFail("Unexpected text") })
            await input.start()
            let problem: VoiceSearchProblem = status == .denied ? .denied(.speech) : .restricted(.speech)
            XCTAssertEqual(input.state, .failed(problem))
            XCTAssertEqual(problem.offersSettings, status == .denied)
            XCTAssertFalse(problem.message.isEmpty)
            XCTAssertTrue(service.permissionRequests.isEmpty)
            XCTAssertEqual(service.starts, 0)
        }
    }

    @MainActor
    func testMicrophoneDenialShowsDistinctProblemWithoutAudio() async {
        let service = VoiceTestService()
        service.microphoneAuthorization = .notDetermined
        service.microphoneResult = .denied
        let input = VoiceSearchModel(service: service, isContextCurrent: { true }, onText: { _ in XCTFail("Unexpected text") })
        await input.start()
        XCTAssertEqual(input.state, .failed(.denied(.microphone)))
        XCTAssertEqual(service.permissionRequests, [.microphone])
        XCTAssertEqual(service.starts, 0)
    }

    @MainActor
    func testUnavailableRecognitionDoesNotRequestUnneededMicrophonePermission() async {
        let service = VoiceTestService()
        service.isAvailable = false
        service.microphoneAuthorization = .notDetermined
        let input = VoiceSearchModel(service: service, isContextCurrent: { true }, onText: { _ in XCTFail("Unexpected text") })
        await input.start()
        XCTAssertEqual(input.state, .failed(.unavailable))
        XCTAssertTrue(service.permissionRequests.isEmpty)
        XCTAssertEqual(service.starts, 0)
    }

    @MainActor
    func testStartFailureStopsAdapterAndCanBeExplicitlyRetried() async {
        let service = VoiceTestService()
        service.startError = .recognition("Mock audio unavailable")
        let input = VoiceSearchModel(service: service, isContextCurrent: { true }, onText: { _ in })
        await input.start()
        XCTAssertEqual(input.state, .failed(.recognition("Mock audio unavailable")))
        XCTAssertFalse(service.isListening)
        service.startError = nil
        await input.start()
        XCTAssertEqual(input.state, .listening)
        XCTAssertEqual(service.starts, 2)
        input.cancel()
    }

    @MainActor
    func testPartialTextDoesNotChangeQueryAndFindCommitsOnce() async {
        let service = VoiceTestService()
        var results: [String] = []
        let input = VoiceSearchModel(service: service, isContextCurrent: { true }, onText: { results.append($0) })
        await input.start()
        service.emit(.transcript(" Наруто ", isFinal: false))
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(input.transcript, " Наруто ")
        XCTAssertTrue(input.canUseTranscript)
        input.useTranscript()
        XCTAssertEqual(results, ["Наруто"])
        XCTAssertEqual(input.state, .completed)
        XCTAssertFalse(service.isListening)
        service.emit(.transcript("Old callback", isFinal: true))
        input.useTranscript()
        XCTAssertEqual(results, ["Наруто"])
    }

    @MainActor
    func testBlankFinalResultIsFailureNotEmptySearch() async {
        let service = VoiceTestService()
        let input = VoiceSearchModel(service: service, isContextCurrent: { true }, onText: { _ in XCTFail("Unexpected text") })
        await input.start()
        service.emit(.transcript(" \n\t ", isFinal: true))
        XCTAssertEqual(input.state, .failed(.noSpeech))
        XCTAssertFalse(service.isListening)
        XCTAssertFalse(input.canUseTranscript)
    }

    @MainActor
    func testCancelRejectsLateFinalAndErrorWithoutChangingManualText() async {
        let service = VoiceTestService()
        var query = "Manual input"
        let input = VoiceSearchModel(service: service, isContextCurrent: { true }, onText: { query = $0 })
        await input.start()
        service.emit(.transcript("Partial", isFinal: false))
        input.cancel()
        service.emit(.transcript("Late final", isFinal: true))
        service.emit(.failed(.recognition("Late failure")))
        XCTAssertEqual(query, "Manual input")
        XCTAssertEqual(input.state, .cancelled)
        XCTAssertFalse(service.isListening)
    }

    @MainActor
    func testCancelledPermissionGrantDoesNotRequestMicrophoneLater() async {
        let service = VoiceTestService()
        service.speechAuthorization = .notDetermined
        service.microphoneAuthorization = .notDetermined
        let gate = ProfileTestGate()
        service.speechGate = gate
        let input = VoiceSearchModel(service: service, isContextCurrent: { true }, onText: { _ in XCTFail("Unexpected text") })
        let starting = Task { await input.start() }
        defer { gate.release(); starting.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        input.cancel()
        gate.release()
        await starting.value
        XCTAssertEqual(input.state, .cancelled)
        XCTAssertEqual(service.permissionRequests, [.speech])
        XCTAssertEqual(service.starts, 0)
    }

    @MainActor
    func testCallerTaskCancellationDoesNotLeaveAuthorizationSpinnerOrStartAudio() async {
        let service = VoiceTestService()
        service.microphoneAuthorization = .notDetermined
        let gate = ProfileTestGate()
        service.microphoneGate = gate
        let input = VoiceSearchModel(service: service, isContextCurrent: { true }, onText: { _ in XCTFail("Unexpected text") })
        let starting = Task { await input.start() }
        defer { gate.release(); starting.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        starting.cancel()
        gate.release()
        await starting.value
        XCTAssertEqual(input.state, .cancelled)
        XCTAssertEqual(service.starts, 0)
        XCTAssertFalse(service.isListening)
    }

    @MainActor
    func testRetryRejectsOldTranscriptsAndErrorsWithoutStoppingNewAttempt() async {
        let service = VoiceTestService()
        var results: [String] = []
        let input = VoiceSearchModel(service: service, isContextCurrent: { true }, onText: { results.append($0) })
        await input.start()
        service.emit(.failed(.unavailable))
        await input.start()
        XCTAssertEqual(input.state, .listening)
        service.emit(.transcript("Old", isFinal: true), attempt: 0)
        service.emit(.failed(.noSpeech), attempt: 0)
        XCTAssertEqual(input.state, .listening)
        XCTAssertTrue(service.isListening)
        XCTAssertTrue(results.isEmpty)
        service.emit(.transcript("Current", isFinal: true), attempt: 1)
        XCTAssertEqual(results, ["Current"])
        XCTAssertEqual(input.state, .completed)
    }

    @MainActor
    func testLatePermissionCompletionCannotCancelAnExplicitNewAttempt() async {
        let service = VoiceTestService()
        service.speechAuthorization = .notDetermined
        let gate = ProfileTestGate()
        service.speechGate = gate
        let input = VoiceSearchModel(service: service, isContextCurrent: { true }, onText: { _ in })
        let old = Task { await input.start() }
        defer { gate.release(); old.cancel(); input.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        input.cancel()
        service.speechGate = nil
        await input.start()
        XCTAssertEqual(input.state, .listening)
        gate.release()
        await old.value
        XCTAssertEqual(input.state, .listening)
        XCTAssertEqual(service.starts, 1)
        XCTAssertTrue(service.isListening)
    }

    @MainActor
    func testSynchronousAdapterCompletionOrFailureIsNotReplacedByListening() async {
        for event in [VoiceInputEvent.transcript("Done", isFinal: true), .failed(.unavailable)] {
            let service = VoiceTestService()
            service.startupEvent = event
            var results: [String] = []
            let input = VoiceSearchModel(service: service, isContextCurrent: { true }, onText: { results.append($0) })
            await input.start()
            XCTAssertFalse(service.isListening)
            if event == .failed(.unavailable) { XCTAssertEqual(input.state, .failed(.unavailable)); XCTAssertTrue(results.isEmpty) }
            else { XCTAssertEqual(input.state, .completed); XCTAssertEqual(results, ["Done"]) }
        }
    }
}
