import UIKit
import CoreHaptics

/// Keys behind "Вибро-отклик" in Настройки → Дополнительно. Stored like the other
/// device-only preferences (`DeviceAppearancePreferenceKey`), read directly from
/// `UserDefaults` by `AppHaptics` rather than threaded through the view hierarchy.
enum AppHapticsPreferenceKey {
    static let enabled = "haptics.enabled"
    static let intensity = "haptics.intensity"
    static let categoryPrefix = "haptics.category."
    static let contentReactive = "haptics.contentReactive"
    static let contentSensitivity = "haptics.contentSensitivity"
}

/// How hard a feedback pulse should feel. Scales both the Taptic Engine fallback
/// (`UIImpactFeedbackGenerator.impactOccurred(intensity:)`) and the custom Core
/// Haptics patterns below.
enum AppHapticIntensity: String, CaseIterable, Identifiable {
    case light, normal, strong
    var id: String { rawValue }
    var title: String {
        switch self {
        case .light: return "Лёгкая"
        case .normal: return "Обычная"
        case .strong: return "Сильная"
        }
    }
    var scale: Float {
        switch self {
        case .light: return 0.45
        case .normal: return 0.75
        case .strong: return 1
        }
    }
    static func stored(_ value: String?) -> AppHapticIntensity { value.flatMap(Self.init(rawValue:)) ?? .normal }
}

/// Groups of moments that can be muted independently -- someone may want a buzz on
/// likes and votes but nothing from the player, or the reverse.
enum AppHapticCategory: String, CaseIterable, Identifiable {
    case interface, social, player, system
    var id: String { rawValue }
    var storageKey: String { AppHapticsPreferenceKey.categoryPrefix + rawValue }
    var title: String {
        switch self {
        case .interface: return "Интерфейс"
        case .social: return "Лайки, оценки и закладки"
        case .player: return "Плеер"
        case .system: return "Системные события"
        }
    }
    var detail: String {
        switch self {
        case .interface: return "Переключение вкладок и сегментов."
        case .social: return "Лайк, дизлайк, оценка эпизода, закладки, отправка комментария."
        case .player: return "Пауза/воспроизведение, пропуск опенинга, смена серии, окончание эпизода."
        case .system: return "Успех, ошибки и подтверждение необратимых действий."
        }
    }
    static func isEnabled(_ category: AppHapticCategory, defaults: UserDefaults) -> Bool {
        defaults.object(forKey: category.storageKey) as? Bool ?? true
    }
}

/// How easily a loud moment in the episode's own audio should count as an "impact".
/// Higher sensitivity reacts to smaller spikes above the rolling loudness floor and
/// re-triggers sooner; lower sensitivity waits for a clearer, rarer spike.
enum AppHapticContentSensitivity: String, CaseIterable, Identifiable {
    case low, normal, high
    var id: String { rawValue }
    var title: String {
        switch self {
        case .low: return "Низкая"
        case .normal: return "Обычная"
        case .high: return "Высокая"
        }
    }
    /// How many times louder than the rolling baseline a burst must be.
    var thresholdMultiplier: Float {
        switch self {
        case .low: return 2.6
        case .normal: return 2.0
        case .high: return 1.5
        }
    }
    /// Minimum time between two triggers, so a sustained loud scene buzzes once, not constantly.
    var cooldown: TimeInterval {
        switch self {
        case .low: return 0.45
        case .normal: return 0.32
        case .high: return 0.2
        }
    }
    static func stored(_ value: String?) -> AppHapticContentSensitivity { value.flatMap(Self.init(rawValue:)) ?? .normal }
}

/// A semantic moment in the app, not a raw haptic style. `AppHaptics.play(_:)` maps
/// each one to a feedback style, and -- where the moment is distinctive enough to
/// deserve its own feel -- a short Core Haptics pattern layered on top of it.
enum AppHapticEvent {
    case interfaceTap
    case interfaceToggle
    case likeOn
    case likeOff
    case voteCast
    case bookmarkAdded
    case bookmarkRemoved
    case commentSent
    case commentFailed
    case playbackToggled
    case seekTick
    case introSkipped
    case episodeChanged
    case episodeFinished
    case refreshCompleted
    case success
    case warning
    case error
    case destructiveConfirm
    /// A sudden loud moment detected in the episode's own audio -- a gunshot, an
    /// explosion, a hit. `strength` is 0...1, how far the burst rose above the
    /// scene's recent loudness floor.
    case contentImpact(strength: Double)

    var category: AppHapticCategory {
        switch self {
        case .interfaceTap, .interfaceToggle: return .interface
        case .likeOn, .likeOff, .voteCast, .bookmarkAdded, .bookmarkRemoved, .commentSent, .commentFailed: return .social
        case .playbackToggled, .seekTick, .introSkipped, .episodeChanged, .episodeFinished, .contentImpact: return .player
        case .refreshCompleted, .success, .warning, .error, .destructiveConfirm: return .system
        }
    }

    /// Everything but `contentImpact` plays at full strength; that one carries its
    /// own measured magnitude, scaled further by the user's chosen intensity.
    fileprivate var baseStrength: Float {
        if case .contentImpact(let strength) = self { return Float(max(0, min(1, strength))) }
        return 1
    }

    fileprivate enum Fallback {
        case selection
        case impact(UIImpactFeedbackGenerator.FeedbackStyle)
        case notification(UINotificationFeedbackGenerator.FeedbackType)
    }

    fileprivate var fallback: Fallback {
        switch self {
        case .interfaceTap: return .impact(.light)
        case .interfaceToggle: return .selection
        case .likeOn: return .impact(.medium)
        case .likeOff: return .impact(.soft)
        case .voteCast: return .impact(.light)
        case .bookmarkAdded: return .impact(.medium)
        case .bookmarkRemoved: return .impact(.soft)
        case .commentSent: return .notification(.success)
        case .commentFailed: return .notification(.error)
        case .playbackToggled: return .impact(.light)
        case .seekTick: return .selection
        case .introSkipped: return .impact(.medium)
        case .episodeChanged: return .impact(.medium)
        case .episodeFinished: return .notification(.success)
        case .refreshCompleted: return .impact(.light)
        case .success: return .notification(.success)
        case .warning: return .notification(.warning)
        case .error: return .notification(.error)
        case .destructiveConfirm: return .impact(.heavy)
        case .contentImpact(let strength): return .impact(strength > 0.7 ? .heavy : .medium)
        }
    }

    /// Only the moments worth a distinct shape get a pattern; everything else rides
    /// the plain Taptic fallback above, scaled by intensity.
    fileprivate func pattern(scale: Float) -> [CHHapticEvent]? {
        func transient(at time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * scale),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: time)
        }
        switch self {
        case .likeOn:
            return [transient(at: 0, intensity: 0.7, sharpness: 0.7), transient(at: 0.08, intensity: 1, sharpness: 0.9)]
        case .introSkipped:
            return [transient(at: 0, intensity: 0.5, sharpness: 0.3), transient(at: 0.06, intensity: 0.85, sharpness: 0.75)]
        case .episodeFinished:
            return [
                transient(at: 0, intensity: 0.8, sharpness: 0.5),
                transient(at: 0.12, intensity: 0.8, sharpness: 0.5),
                transient(at: 0.24, intensity: 1, sharpness: 0.6),
            ]
        case .error:
            return [transient(at: 0, intensity: 1, sharpness: 1), transient(at: 0.1, intensity: 1, sharpness: 1)]
        case .contentImpact(let strength):
            return [transient(at: 0, intensity: Float(max(0, min(1, strength))), sharpness: 0.85)]
        default:
            return nil
        }
    }
}

/// Adaptive vibro feedback: the same call site asks for a *moment* (`AppHapticEvent`)
/// and this engine decides how it should feel -- a short Core Haptics pattern when the
/// hardware supports it, otherwise the matching Taptic Engine style -- scaled by the
/// user's chosen intensity, and silenced per-category or entirely from Settings.
@MainActor
final class AppHaptics {
    static let shared = AppHaptics()

    private var engine: CHHapticEngine?
    private let supportsCoreHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private lazy var selection = UISelectionFeedbackGenerator()
    private lazy var notification = UINotificationFeedbackGenerator()
    private lazy var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [
        .light: UIImpactFeedbackGenerator(style: .light),
        .medium: UIImpactFeedbackGenerator(style: .medium),
        .heavy: UIImpactFeedbackGenerator(style: .heavy),
        .soft: UIImpactFeedbackGenerator(style: .soft),
        .rigid: UIImpactFeedbackGenerator(style: .rigid),
    ]

    private init() {
        guard supportsCoreHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
    }

    func play(_ event: AppHapticEvent, defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: AppHapticsPreferenceKey.enabled) as? Bool ?? true else { return }
        guard AppHapticCategory.isEnabled(event.category, defaults: defaults) else { return }
        if case .contentImpact = event {
            guard defaults.bool(forKey: AppHapticsPreferenceKey.contentReactive) else { return }
        }
        let intensity = AppHapticIntensity.stored(defaults.string(forKey: AppHapticsPreferenceKey.intensity))

        if supportsCoreHaptics, let events = event.pattern(scale: intensity.scale), playPattern(events) {
            return
        }
        playFallback(event.fallback, scale: intensity.scale * event.baseStrength)
    }

    /// Whether the audio-reactive tap should attach to the next item the embedded
    /// player loads. Read at install time -- the player does not re-check this
    /// mid-episode.
    func isContentReactiveEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: AppHapticsPreferenceKey.enabled) as? Bool ?? true
            && AppHapticCategory.isEnabled(.player, defaults: defaults)
            && defaults.bool(forKey: AppHapticsPreferenceKey.contentReactive)
    }

    func contentSensitivity(defaults: UserDefaults = .standard) -> AppHapticContentSensitivity {
        .stored(defaults.string(forKey: AppHapticsPreferenceKey.contentSensitivity))
    }

    private func playPattern(_ events: [CHHapticEvent]) -> Bool {
        guard let engine else { return false }
        do {
            try engine.start()
            let player = try engine.makePlayer(with: try CHHapticPattern(events: events, parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            return false
        }
    }

    private func playFallback(_ fallback: AppHapticEvent.Fallback, scale: Float) {
        switch fallback {
        case .selection:
            selection.selectionChanged()
            selection.prepare()
        case .impact(let style):
            let generator = impactGenerators[style] ?? UIImpactFeedbackGenerator(style: style)
            generator.impactOccurred(intensity: CGFloat(scale))
            generator.prepare()
        case .notification(let type):
            notification.notificationOccurred(type)
            notification.prepare()
        }
    }
}
