import AVFoundation
import Foundation
import UIKit
import XCTest
@testable import Anixart

@MainActor
final class VoiceTestService: VoiceInputService {
    var speechAuthorization: VoicePermissionStatus = .authorized
    var microphoneAuthorization: VoicePermissionStatus = .authorized
    var speechResult: VoicePermissionStatus = .authorized
    var microphoneResult: VoicePermissionStatus = .authorized
    var isAvailable = true
    var speechGate: ProfileTestGate?
    var microphoneGate: ProfileTestGate?
    var startError: VoiceSearchProblem?
    var startupEvent: VoiceInputEvent?
    private(set) var permissionRequests: [VoicePermission] = []
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var isListening = false
    private(set) var handlers: [@MainActor (VoiceInputEvent) -> Void] = []
    let started = XCTestExpectation(description: "Mock voice input started")
    var onStopped: (() -> Void)?

    func requestSpeechAuthorization() async -> VoicePermissionStatus {
        permissionRequests.append(.speech)
        await speechGate?.wait()
        speechAuthorization = speechResult
        return speechResult
    }
    func requestMicrophoneAuthorization() async -> VoicePermissionStatus {
        permissionRequests.append(.microphone)
        await microphoneGate?.wait()
        microphoneAuthorization = microphoneResult
        return microphoneResult
    }
    func start(onEvent: @escaping @MainActor (VoiceInputEvent) -> Void) throws {
        starts += 1
        isListening = true
        handlers.append(onEvent)
        if starts == 1 { started.fulfill() }
        if let startupEvent { onEvent(startupEvent) }
        if let startError { throw startError }
    }
    func stop() {
        stops += 1
        let wasListening = isListening
        isListening = false
        if wasListening { onStopped?() }
    }
    /// Deliberately delivers after stop/retry, to model late OS callbacks.
    func emit(_ event: VoiceInputEvent, attempt: Int? = nil) {
        guard !handlers.isEmpty else { return }
        handlers[attempt ?? handlers.count - 1](event)
    }
}

@MainActor
final class GalleryTestLoader: GalleryImageLoading {
    struct Plan { let image: UIImage?; let gate: ProfileTestGate? }
    var plans: [URL: [Plan]] = [:]
    private(set) var requests: [ImageRequestKey] = []
    private(set) var retryRequests: [ImageRequestKey] = []
    let defaultImage = UIImage()

    func enqueue(_ url: URL, image: UIImage?, gate: ProfileTestGate? = nil) {
        plans[url, default: []].append(Plan(image: image, gate: gate))
    }
    func image(for url: URL, pixelSize: CGFloat) async -> UIImage? {
        requests.append(ImageRequestKey(url: url, pixelSize: pixelSize))
        let plan: Plan
        if plans[url]?.isEmpty == false { plan = plans[url]!.removeFirst() }
        else { plan = Plan(image: defaultImage, gate: nil) }
        await plan.gate?.wait() // Intentionally ignores cancellation.
        return plan.image
    }
    func retryImage(for url: URL, pixelSize: CGFloat) async -> UIImage? {
        retryRequests.append(ImageRequestKey(url: url, pixelSize: pixelSize))
        return await image(for: url, pixelSize: pixelSize)
    }
}

@MainActor
final class VoiceAudioTestSession: VoiceAudioSessionControlling {
    enum Failure: Error { case refused }
    enum Call: Equatable {
        case configure(VoiceAudioConfiguration)
        case active(Bool, notifyOthers: Bool)
    }
    var configuration: VoiceAudioConfiguration
    private(set) var calls: [Call] = []
    var rejectsActivation = false
    var rejectedConfiguration: VoiceAudioConfiguration?
    var normalizedRecording: VoiceAudioConfiguration?

    init(_ configuration: VoiceAudioConfiguration) { self.configuration = configuration }
    func configure(_ configuration: VoiceAudioConfiguration) throws {
        calls.append(.configure(configuration))
        if rejectedConfiguration == configuration { throw Failure.refused }
        self.configuration = configuration == .recording ? normalizedRecording ?? configuration : configuration
    }
    func setActive(_ active: Bool, notifyOthers: Bool) throws {
        calls.append(.active(active, notifyOthers: notifyOthers))
        if active, rejectsActivation { throw Failure.refused }
    }
}
