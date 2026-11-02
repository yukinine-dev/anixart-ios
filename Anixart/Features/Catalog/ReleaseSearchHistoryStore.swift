import Foundation
import AnixartKit

/// Device-local query history, separated by account/guest. Tokens and catalogue
/// results are never persisted. Only explicit search/use actions add entries.
@MainActor
@Observable
final class ReleaseSearchHistoryStore {
    struct Entry: Codable, Hashable, Identifiable {
        let query: String
        let scope: SearchScope
        let usedAt: Date
        var id: String { "\(scope.rawValue):\(query.lowercased())" }
    }

    static let limit = 20
    let profileID: Int?
    private let defaults: UserDefaults
    private var storageKey: String { "search.release.history.\(profileID.map { String($0) } ?? "guest")" }
    private(set) var entries: [Entry] = []

    init(profileID: Int?, defaults: UserDefaults = .standard) {
        self.profileID = profileID
        self.defaults = defaults
        reload()
    }

    func reload() {
        guard let data = defaults.data(forKey: storageKey), data.count <= 128 * 1024,
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { entries = []; return }
        entries = Self.normalized(decoded)
    }

    func remember(query: String, scope: SearchScope, now: Date = .now) {
        guard let query = Self.query(query), SearchScope.titleSearchScopes.contains(scope),
              now.timeIntervalSince1970.isFinite else { return }
        // Another scene/search entry may have updated this account's preferences
        // since this snapshot was created. Never replace its queries with stale ones.
        reload()
        let entry = Entry(query: query, scope: scope, usedAt: now)
        entries = Self.normalized([entry] + entries.filter { $0.id != entry.id })
        persist()
    }

    @discardableResult
    func remove(id: String) -> Bool {
        reload()
        guard entries.contains(where: { $0.id == id }) else { return false }
        entries.removeAll { $0.id == id }
        persist()
        return true
    }

    func clear() {
        entries = []
        defaults.removeObject(forKey: storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func query(_ value: String) -> String? {
        let value = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !value.isEmpty, value.utf16.count <= 300 else { return nil }
        return value
    }

    private static func normalized(_ values: [Entry]) -> [Entry] {
        var seen = Set<String>()
        return Array(values.compactMap { value -> Entry? in
            guard let query = Self.query(value.query), SearchScope.titleSearchScopes.contains(value.scope),
                  value.usedAt.timeIntervalSince1970.isFinite else { return nil }
            let entry = Entry(query: query, scope: value.scope, usedAt: value.usedAt)
            return seen.insert(entry.id).inserted ? entry : nil
        }.prefix(limit))
    }
}
