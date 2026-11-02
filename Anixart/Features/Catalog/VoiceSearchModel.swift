import Foundation
import Observation

enum VoicePermission: Equatable, Sendable {
    case speech, microphone
}

enum VoicePermissionStatus: Equatable, Sendable {
    case notDetermined, authorized, denied, restricted
}

enum VoiceSearchProblem: Error, Equatable, Sendable {
    case denied(VoicePermission)
    case restricted(VoicePermission)
    case unavailable
    case noSpeech
    case recognition(String)

    var message: String {
        switch self {
        case .denied(.speech): return "Разрешите распознавание речи для Anixart в настройках iOS или введите название вручную."
        case .denied(.microphone): return "Разрешите доступ к микрофону для Anixart в настройках iOS или введите название вручную."
        case .restricted: return "Голосовой ввод ограничен настройками устройства. Название можно ввести вручную."
        case .unavailable: return "Распознавание речи сейчас недоступно. Проверьте подключение к сети или введите название вручную."
        case .noSpeech: return "Не удалось распознать речь. Попробуйте ещё раз или введите название вручную."
        case .recognition(let message): return message
        }
    }

    var offersSettings: Bool {
        if case .denied = self { return true }
        return false
    }
}

enum VoiceInputEvent: Equatable, Sendable {
    case transcript(String, isFinal: Bool)
    case failed(VoiceSearchProblem)
}

/// Tests replace the adapter: no OS permissions, audio sessions or microphone.
@MainActor
protocol VoiceInputService: AnyObject, Sendable {
    var speechAuthorization: VoicePermissionStatus { get }
    var microphoneAuthorization: VoicePermissionStatus { get }
    var isAvailable: Bool { get }
    func requestSpeechAuthorization() async -> VoicePermissionStatus
    func requestMicrophoneAuthorization() async -> VoicePermissionStatus
    func start(onEvent: @escaping @MainActor (VoiceInputEvent) -> Void) throws
    func stop()
}

/// A single explicit voice-input attempt. Partial text stays in the sheet; only
/// a final result or the user's Find action can change the scoped search query.
@MainActor
@Observable
final class VoiceSearchModel {
    enum State: Equatable {
        case idle, authorizing(VoicePermission), starting, listening
        case failed(VoiceSearchProblem), completed, cancelled
    }

    private(set) var state: State = .idle
    private(set) var transcript = ""
    @ObservationIgnored private let service: any VoiceInputService
    @ObservationIgnored private let isContextCurrent: @MainActor () -> Bool
    @ObservationIgnored private let onText: @MainActor (String) -> Void
    private var generation = 0

    init(service: any VoiceInputService,
         isContextCurrent: @escaping @MainActor () -> Bool,
         onText: @escaping @MainActor (String) -> Void) {
        self.service = service
        self.isContextCurrent = isContextCurrent
        self.onText = onText
    }

    deinit {
        Task { @MainActor [service] in service.stop() }
    }

    var canUseTranscript: Bool {
        state == .listening && !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Called only by the microphone button or an explicit Retry, never on mount.
    func start() async {
        guard isContextCurrent(), !Task.isCancelled else { cancel(); return }
        generation += 1
        let token = generation
        service.stop()
        transcript = ""
        observeContext(generation: token)
        await withTaskCancellationHandler {
            await authorizeAndStart(generation: token)
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.cancel()
            }
        }
    }

    func useTranscript() {
        guard canUseTranscript else { return }
        complete(generation: generation)
    }

    func cancel() {
        guard state != .completed, state != .cancelled else { return }
        generation += 1
        service.stop()
        state = .cancelled
    }

    private func authorizeAndStart(generation token: Int) async {
        do {
            try checkContext(generation: token)
            var speech = service.speechAuthorization
            if speech == .notDetermined {
                state = .authorizing(.speech)
                speech = await service.requestSpeechAuthorization()
                try checkContext(generation: token)
            }
            try require(speech, permission: .speech)
            guard service.isAvailable else { throw VoiceSearchProblem.unavailable }
            var microphone = service.microphoneAuthorization
            if microphone == .notDetermined {
                state = .authorizing(.microphone)
                microphone = await service.requestMicrophoneAuthorization()
                try checkContext(generation: token)
            }
            try require(microphone, permission: .microphone)
            try checkContext(generation: token)
            guard service.isAvailable else { throw VoiceSearchProblem.unavailable }
            state = .starting
            try service.start { [weak self] event in self?.receive(event, generation: token) }
            // An adapter may fail or finish synchronously from start().
            guard token == generation else { return }
            try checkContext(generation: token)
            state = .listening
        } catch {
            guard token == generation else { return }
            if !isContextCurrent() || error is CancellationError || Task.isCancelled { cancel() }
            else { fail((error as? VoiceSearchProblem) ?? .recognition(error.localizedDescription)) }
        }
    }

    private func require(_ status: VoicePermissionStatus, permission: VoicePermission) throws {
        switch status {
        case .authorized: break
        case .denied: throw VoiceSearchProblem.denied(permission)
        case .restricted, .notDetermined: throw VoiceSearchProblem.restricted(permission)
        }
    }

    private func checkContext(generation token: Int) throws {
        try Task.checkCancellation()
        guard token == generation, isContextCurrent() else { throw CancellationError() }
    }

    private func receive(_ event: VoiceInputEvent, generation token: Int) {
        guard token == generation else { return }
        guard isContextCurrent() else { cancel(); return }
        guard state == .starting || state == .listening else { return }
        switch event {
        case .transcript(let text, let isFinal):
            transcript = text
            if isFinal { complete(generation: token) }
        case .failed(let problem): fail(problem)
        }
    }

    private func complete(generation token: Int) {
        guard token == generation, isContextCurrent() else { cancel(); return }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { fail(.noSpeech); return }
        generation += 1
        service.stop()
        state = .completed
        onText(text)
    }

    private func fail(_ problem: VoiceSearchProblem) {
        generation += 1
        service.stop()
        state = .failed(problem)
    }

    /// Account/query/visibility changes retire recording even if no recognizer
    /// callback arrives and the view's onChange has not run yet.
    private func observeContext(generation token: Int) {
        withObservationTracking {
            _ = isContextCurrent()
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.cancel()
            }
        }
    }
}
