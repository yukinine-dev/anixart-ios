import Foundation
import Observation

/// Device-local choices. SF Pro is provided by Apple's system font APIs, not assets.
enum AppTypeface: String, CaseIterable, Identifiable {
    case roboto
    case sfPro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .roboto: return "Roboto"
        case .sfPro: return "SF Pro (системный)"
        }
    }

    init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .roboto
    }
}

/// Observation also tracks reads made inside `Font.ax`, so existing explicit font
/// modifiers refresh without replacing their views or resetting navigation state.
/// Reads remain synchronous for those helpers; mutations happen on the main actor.
@Observable
final class AppTypefacePreferences {
    static let shared = AppTypefacePreferences()

    private let defaults: UserDefaults
    private(set) var typeface: AppTypeface

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        typeface = AppTypeface(storedValue: defaults.object(forKey: AppFont.preferenceStorageKey) as? String)
    }

    @MainActor
    func setTypeface(_ typeface: AppTypeface) {
        defaults.set(typeface.rawValue, forKey: AppFont.preferenceStorageKey)
        guard self.typeface != typeface else { return }
        self.typeface = typeface
    }

    /// The root typography modifier observes UserDefaults through AppStorage and
    /// calls this for external writes, removals, and when a scene becomes active.
    @MainActor
    func reload() {
        let stored = AppTypeface(storedValue: defaults.object(forKey: AppFont.preferenceStorageKey) as? String)
        guard typeface != stored else { return }
        typeface = stored
    }
}
