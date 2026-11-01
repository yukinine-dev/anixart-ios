import Foundation
import AnixartKit

/// Per-account history. Foreign profile reads never consult or update this cache.
@MainActor
enum ProfileRecentBadges {
    private static func idsKey(_ profileID: Int) -> String { "profile.\(profileID).recentBadgeIDs" }
    private static func objectsKey(_ profileID: Int) -> String { "profile.\(profileID).recentBadges" }

    static func ids(profileID: Int, defaults: UserDefaults = .standard) -> [Int] {
        ProfileBadgePresentation.recentIDs(defaults.array(forKey: idsKey(profileID)) as? [Int] ?? [])
    }

    static func badges(profileID: Int, defaults: UserDefaults = .standard) -> [Badge] {
        guard let data = defaults.data(forKey: objectsKey(profileID)),
              let cached = try? JSONDecoder().decode([Badge].self, from: data) else { return [] }
        let byID = Dictionary(ProfileBadgePresentation.unique(cached).map { ($0.id, $0) },
                              uniquingKeysWith: { first, _ in first })
        return ids(profileID: profileID, defaults: defaults).compactMap { byID[$0] }
    }

    /// Retains compatibility with the existing ID-only cache without fabricating
    /// a Badge object for an ID whose artwork/ownership has never been loaded.
    static func record(_ id: Int, profileID: Int, defaults: UserDefaults = .standard) {
        let previous = badges(profileID: profileID, defaults: defaults)
        let orderedIDs = ProfileEditorRules.recentBadgeIDs(adding: id, to: ids(profileID: profileID, defaults: defaults))
        defaults.set(orderedIDs, forKey: idsKey(profileID))
        writeObjects(previous.filter { orderedIDs.contains($0.id) }, profileID: profileID, defaults: defaults)
    }

    static func record(_ badge: Badge, profileID: Int, defaults: UserDefaults = .standard) {
        guard badge.id > 0 else { return }
        let previous = badges(profileID: profileID, defaults: defaults)
        let orderedIDs = ProfileEditorRules.recentBadgeIDs(adding: badge.id, to: ids(profileID: profileID, defaults: defaults))
        let byID = Dictionary(ProfileBadgePresentation.unique([badge] + previous).map { ($0.id, $0) },
                              uniquingKeysWith: { first, _ in first })
        defaults.set(orderedIDs, forKey: idsKey(profileID))
        writeObjects(orderedIDs.compactMap { byID[$0] }, profileID: profileID, defaults: defaults)
    }

    static func query(profileID: Int, defaults: UserDefaults = .standard) -> String {
        ProfileBadgePresentation.recentQuery(ids(profileID: profileID, defaults: defaults))
    }

    static func refresh(_ response: ProfileBadgeSectionsResponse, profileID: Int,
                        defaults: UserDefaults = .standard) -> [Badge] {
        if response.recent != nil {
            let current = ProfileBadgePresentation.recent(previousIDs: ids(profileID: profileID, defaults: defaults),
                                                          response: response)
            defaults.set(current.map(\.id), forKey: idsKey(profileID))
            writeObjects(current, profileID: profileID, defaults: defaults)
            return current
        }
        // An omitted field is not evidence that the server removed the history.
        // Preserve legacy IDs until the endpoint actually supplies fresh entries.
        if let selected = response.profile?.selectedBadge {
            let fallback = badges(profileID: profileID, defaults: defaults).first { $0.id == selected.id } ?? selected
            record(ProfileBadgePresentation.resolved(fallback, in: response), profileID: profileID, defaults: defaults)
        }
        let current = badges(profileID: profileID, defaults: defaults)
            .map { ProfileBadgePresentation.resolved($0, in: response) }
        writeObjects(current, profileID: profileID, defaults: defaults)
        return current
    }

    private static func writeObjects(_ badges: [Badge], profileID: Int, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(Array(badges.prefix(ProfileEditorRules.recentBadgeLimit))) else { return }
        defaults.set(data, forKey: objectsKey(profileID))
    }
}
