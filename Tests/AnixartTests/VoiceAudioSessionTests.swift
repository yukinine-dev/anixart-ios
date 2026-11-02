import AVFoundation
import XCTest
@testable import Anixart

final class VoiceAudioSessionTests: XCTestCase {
    @MainActor
    func testRecordingConfigurationDoesNotUseUnsupportedDuckingOrMixingOptions() {
        XCTAssertEqual(VoiceAudioConfiguration.recording.category, .record)
        XCTAssertEqual(VoiceAudioConfiguration.recording.mode, .measurement)
        XCTAssertTrue(VoiceAudioConfiguration.recording.options.isEmpty)
    }

    @MainActor
    func testIdleLeaseNeverConfiguresOrActivatesAudio() {
        let previous = VoiceAudioConfiguration(category: .ambient, mode: .default, options: [])
        let audio = VoiceAudioTestSession(previous)
        let lease = VoiceAudioSessionLease(audioSession: audio)
        XCTAssertNil(lease.release())
        XCTAssertTrue(audio.calls.isEmpty)
    }

    @MainActor
    func testRecordingRestoresExactCategoryModeAndOptionsWithoutDeactivatingPlayer() throws {
        let previous = VoiceAudioConfiguration(category: .playback, mode: .moviePlayback, options: .mixWithOthers)
        let audio = VoiceAudioTestSession(previous)
        let lease = VoiceAudioSessionLease(audioSession: audio)
        try lease.acquire()
        XCTAssertEqual(audio.configuration, .recording)
        XCTAssertNil(lease.release())
        XCTAssertEqual(audio.configuration, previous)
        XCTAssertEqual(audio.calls, [.configure(.recording), .active(true, notifyOthers: false), .configure(previous)])
    }

    @MainActor
    func testNonPlaybackSessionDeactivatesAndNotifiesOtherAudioThenRestores() throws {
        let previous = VoiceAudioConfiguration(category: .soloAmbient, mode: .default, options: [])
        let audio = VoiceAudioTestSession(previous)
        let lease = VoiceAudioSessionLease(audioSession: audio)
        try lease.acquire()
        XCTAssertNil(lease.release())
        XCTAssertEqual(audio.calls, [.configure(.recording), .active(true, notifyOthers: false),
                                    .active(false, notifyOthers: true), .configure(previous)])
    }

    @MainActor
    func testCleanupDoesNotOverwriteANewerPlayerConfiguration() throws {
        let previous = VoiceAudioConfiguration(category: .ambient, mode: .default, options: [])
        let newer = VoiceAudioConfiguration(category: .playback, mode: .moviePlayback, options: [])
        let audio = VoiceAudioTestSession(previous)
        let lease = VoiceAudioSessionLease(audioSession: audio)
        try lease.acquire()
        audio.configuration = newer
        let before = audio.calls
        XCTAssertNil(lease.release())
        XCTAssertEqual(audio.configuration, newer)
        XCTAssertEqual(audio.calls, before)
    }

    @MainActor
    func testFailedActivationStillRestoresConfigurationAndReleasesMicrophoneCategory() {
        let previous = VoiceAudioConfiguration(category: .ambient, mode: .default, options: [])
        let audio = VoiceAudioTestSession(previous)
        audio.rejectsActivation = true
        let lease = VoiceAudioSessionLease(audioSession: audio)
        XCTAssertThrowsError(try lease.acquire())
        XCTAssertEqual(audio.configuration, previous)
        XCTAssertEqual(audio.calls.last, .configure(previous))
        XCTAssertTrue(audio.calls.contains(.active(false, notifyOthers: true)))
    }

    @MainActor
    func testAcquireAndReleaseAreIdempotentAndRestoreFailureDeactivatesRecording() throws {
        let previous = VoiceAudioConfiguration(category: .playback, mode: .moviePlayback, options: [])
        let audio = VoiceAudioTestSession(previous)
        let lease = VoiceAudioSessionLease(audioSession: audio)
        try lease.acquire()
        let started = audio.calls
        try lease.acquire()
        XCTAssertEqual(audio.calls, started)
        audio.rejectedConfiguration = previous
        XCTAssertNotNil(lease.release())
        XCTAssertEqual(audio.calls.last, .active(false, notifyOthers: true))
        let stopped = audio.calls
        XCTAssertNil(lease.release())
        XCTAssertEqual(audio.calls, stopped)
    }

    @MainActor
    func testOSNormalizedRecordingConfigurationStillRestoresThePlayer() throws {
        let previous = VoiceAudioConfiguration(category: .playback, mode: .moviePlayback, options: [])
        let audio = VoiceAudioTestSession(previous)
        audio.normalizedRecording = VoiceAudioConfiguration(category: .record, mode: .default, options: [])
        let lease = VoiceAudioSessionLease(audioSession: audio)
        try lease.acquire()
        XCTAssertNotEqual(audio.configuration, .recording)
        XCTAssertNil(lease.release())
        XCTAssertEqual(audio.configuration, previous)
        XCTAssertEqual(audio.calls.last, .configure(previous))
    }
}
