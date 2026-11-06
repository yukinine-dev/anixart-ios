import SwiftUI
import Observation

/// Which player an episode opens in, as the Android "Выберите плеер" dialog offers.
///
/// АниксПлеер is deliberately absent: on Android it is a separate downloadable
/// player, and the dialog there carries a download button for it.
enum PlayerChoice: String, CaseIterable, Identifiable, Sendable {
    case web
    case embedded
    case external

    var id: String { rawValue }

    var title: String {
        switch self {
        case .web: return "Веб-плеер"
        case .embedded: return "Встроенный плеер"
        case .external: return "Сторонний плеер"
        }
    }

    var summary: String {
        switch self {
        case .web: return "Просмотр в плеере источника. Стандартный вариант."
        case .embedded: return "Простой и удобный, не требует отдельного скачивания."
        case .external: return "Просмотр в любом плеере, который установлен на вашем устройстве."
        }
    }
}

/// The playback preferences the two dialogs write to, kept in `UserDefaults` so a
/// "не спрашивать" sticks across launches.
@MainActor
@Observable
final class PlaybackPreferences {
    private enum Key {
        static let choice = "playback.player"
        static let alwaysAsk = "playback.alwaysAsk"
        static let acceptedDisclaimer = "playback.acceptedDisclaimer"
        static let enhanceExplained = "playback.enhanceExplained"
        static let rewindSeconds = "playback.rewindSeconds"
        static let enhanceStrength = "playback.enhanceStrength"
    }

    private let defaults: UserDefaults

    private(set) var choice: PlayerChoice
    private(set) var alwaysAsk: Bool
    /// The warning about third-party sources is shown once, as on Android.
    private(set) var hasAcceptedDisclaimer: Bool
    private(set) var hasSeenEnhanceExplainer: Bool
    /// "Пропустить заставку" jumps this far. The Android hint recommends 1:25.
    private(set) var rewindSeconds: Int
    /// How hard the enhancement pushes. The APK has no such setting; this is
    /// here because how sharp is too sharp is a matter of taste.
    private(set) var enhanceStrength: VideoEnhanceFilter.Strength

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.choice = PlayerChoice(rawValue: defaults.string(forKey: Key.choice) ?? "") ?? .web
        self.alwaysAsk = defaults.object(forKey: Key.alwaysAsk) as? Bool ?? true
        self.hasAcceptedDisclaimer = defaults.bool(forKey: Key.acceptedDisclaimer)
        self.hasSeenEnhanceExplainer = defaults.bool(forKey: Key.enhanceExplained)
        self.rewindSeconds = defaults.object(forKey: Key.rewindSeconds) as? Int ?? 85
        self.enhanceStrength = VideoEnhanceFilter.Strength(
            rawValue: defaults.object(forKey: Key.enhanceStrength) as? Int ?? 1
        ) ?? .medium
    }

    func save(choice: PlayerChoice, alwaysAsk: Bool) {
        self.choice = choice
        self.alwaysAsk = alwaysAsk
        defaults.set(choice.rawValue, forKey: Key.choice)
        defaults.set(alwaysAsk, forKey: Key.alwaysAsk)
    }

    /// Settings and player sheets may hold different instances of these device preferences.
    func reload() {
        choice = PlayerChoice(rawValue: defaults.string(forKey: Key.choice) ?? "") ?? .web
        alwaysAsk = defaults.object(forKey: Key.alwaysAsk) as? Bool ?? true
        hasAcceptedDisclaimer = defaults.bool(forKey: Key.acceptedDisclaimer)
        hasSeenEnhanceExplainer = defaults.bool(forKey: Key.enhanceExplained)
        rewindSeconds = max(0, defaults.object(forKey: Key.rewindSeconds) as? Int ?? 85)
        enhanceStrength = VideoEnhanceFilter.Strength(
            rawValue: defaults.object(forKey: Key.enhanceStrength) as? Int ?? 1
        ) ?? .medium
    }

    func acceptDisclaimer() {
        hasAcceptedDisclaimer = true
        defaults.set(true, forKey: Key.acceptedDisclaimer)
    }

    func markEnhanceExplained() {
        hasSeenEnhanceExplainer = true
        defaults.set(true, forKey: Key.enhanceExplained)
    }

    func setRewindSeconds(_ seconds: Int) {
        rewindSeconds = seconds
        defaults.set(seconds, forKey: Key.rewindSeconds)
    }

    func setEnhanceStrength(_ strength: VideoEnhanceFilter.Strength) {
        enhanceStrength = strength
        defaults.set(strength.rawValue, forKey: Key.enhanceStrength)
    }
}
