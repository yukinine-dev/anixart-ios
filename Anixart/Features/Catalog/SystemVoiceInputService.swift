import AVFoundation
import Foundation
import Speech
import os

/// Native, short-lived recognition. Construction itself does not ask permission
/// or configure audio; only start(), reached after an explicit user tap, does.
@MainActor
final class SystemVoiceInputService: NSObject, VoiceInputService, SFSpeechRecognizerDelegate {
    private static let log = Logger(subsystem: "app.anixart.client", category: "voice-search")
    private static weak var activeService: SystemVoiceInputService?
    private let recognizer: SFSpeechRecognizer?
    private let audioLease: VoiceAudioSessionLease
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var hasTap = false
    private var interruptionObserver: NSObjectProtocol?
    private var timeoutTask: Task<Void, Never>?
    private var onEvent: (@MainActor (VoiceInputEvent) -> Void)?
    private var generation = 0

    override init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
        audioLease = VoiceAudioSessionLease(audioSession: SystemVoiceAudioSession())
        super.init()
        recognizer?.delegate = self
    }

    var speechAuthorization: VoicePermissionStatus {
        Self.permission(SFSpeechRecognizer.authorizationStatus())
    }

    var microphoneAuthorization: VoicePermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .authorized
        case .denied: return .denied
        case .undetermined: return .notDetermined
        @unknown default: return .restricted
        }
    }

    var isAvailable: Bool { recognizer?.isAvailable == true }

    func requestSpeechAuthorization() async -> VoicePermissionStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: Self.permission(status))
            }
        }
    }

    func requestMicrophoneAuthorization() async -> VoicePermissionStatus {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted ? .authorized : .denied)
            }
        }
    }

    func start(onEvent: @escaping @MainActor (VoiceInputEvent) -> Void) throws {
        stop()
        guard speechAuthorization == .authorized, microphoneAuthorization == .authorized,
              let recognizer, recognizer.isAvailable else { throw VoiceSearchProblem.unavailable }
        // AVAudioSession is process-global, even with multiple active iPad scenes.
        // A new explicit voice attempt retires the old recorder before acquiring
        // audio, so its later cleanup cannot restore over a newer voice session.
        if let previous = Self.activeService, previous !== self {
            let notify = previous.onEvent
            previous.stop()
            notify?(.failed(.recognition("Голосовой ввод начат на другом экране. Попробуйте ещё раз или введите название вручную.")))
        }
        Self.activeService = self
        generation += 1
        let token = generation
        self.onEvent = onEvent
        do {
            try audioLease.acquire()
            let engine = AVAudioEngine()
            self.engine = engine
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw VoiceSearchProblem.recognition("Микрофон недоступен. Введите название вручную.")
            }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .search
            // Prefer local recognition where iOS supports it, without claiming
            // that every supported device/language works without Apple's service.
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            self.request = request
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal == true
                let failure = error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    if let text { self.onEvent?(.transcript(text, isFinal: isFinal)) }
                    if !isFinal, let failure { self.onEvent?(.failed(.recognition(failure))) }
                }
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            hasTap = true
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.onEvent?(.failed(.recognition("Голосовой ввод прерван. Попробуйте ещё раз или введите название вручную.")))
                    self.stop()
                }
            }
            engine.prepare()
            try engine.start()
            timeoutTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
                guard let self, self.generation == token else { return }
                self.onEvent?(.failed(.recognition("Голосовой ввод завершён по времени. Попробуйте ещё раз или введите название вручную.")))
                self.stop()
            }
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if Self.activeService === self { Self.activeService = nil }
        generation += 1
        onEvent = nil
        engine?.stop()
        if hasTap { engine?.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio()
        recognition?.cancel()
        recognition = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        request = nil
        engine = nil
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        if let error = audioLease.release() {
            Self.log.error("Could not restore audio session: \(error, privacy: .public)")
        }
    }

    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        guard !available else { return }
        Task { @MainActor [weak self] in
            guard let self, self.onEvent != nil, self.recognizer?.isAvailable == false else { return }
            self.onEvent?(.failed(.unavailable))
            self.stop()
        }
    }

    private nonisolated static func permission(_ status: SFSpeechRecognizerAuthorizationStatus) -> VoicePermissionStatus {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .restricted
        }
    }
}
