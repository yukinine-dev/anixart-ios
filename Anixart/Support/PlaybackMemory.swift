import Foundation

/// What the built-in player remembers about a release between episodes: the speed
/// the viewer chose, the picture height, and where in an episode they pressed
/// «Пропустить заставку». Stored on the device only, keyed by the release title.
enum PlaybackMemory {
    private static let storageKey = "playback.memory"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: PlaybackPreferenceKey.remembersPerRelease) as? Bool ?? true
    }

    static func value(_ field: String, release: String) -> Double? {
        guard isEnabled, !release.isEmpty else { return nil }
        let all = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: [String: Double]]
        return all?[release]?[field]
    }

    static func store(_ value: Double?, field: String, release: String) {
        guard isEnabled, !release.isEmpty else { return }
        var all = (UserDefaults.standard.dictionary(forKey: storageKey) as? [String: [String: Double]]) ?? [:]
        var entry = all[release] ?? [:]
        entry[field] = value
        all[release] = entry
        // The list is only a convenience; keep it from growing without bound.
        if all.count > 400, let oldest = all.keys.first(where: { $0 != release }) { all[oldest] = nil }
        UserDefaults.standard.set(all, forKey: storageKey)
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

/// Lets a screen that lists episodes learn that the player played one to its
/// natural end, without threading a callback through every layer in between.
@MainActor
@Observable
final class PlaybackEvents {
    static let shared = PlaybackEvents()
    private(set) var endedCount = 0
    func reportEnded() { endedCount += 1 }
}
