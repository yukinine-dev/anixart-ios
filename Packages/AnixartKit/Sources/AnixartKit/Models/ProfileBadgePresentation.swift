import Foundation

/// Server order is authoritative. An overflow arrow only replaces the last tile
/// of a full row when that tile is not pinned; seven is not a universal limit.
public struct ProfileBadgePreview: Equatable, Sendable {
    public static let columnCount = 4
    public let badges: [Badge]
    public let totalCount: Int
    public let remainingCount: Int
    public var hasMore: Bool { remainingCount > 0 }
    public var isEmpty: Bool { badges.isEmpty && !hasMore }

    public init(badges: [Badge], totalCount: Int?, columns: Int = ProfileBadgePreview.columnCount) {
        let source = ProfileBadgePresentation.unique(badges)
        let total = max(totalCount ?? 0, source.count)
        let hasMore = total > source.count
        if hasMore, source.count.isMultiple(of: max(1, columns)), source.last?.isShowcased != true {
            self.badges = Array(source.dropLast())
        } else {
            self.badges = source
        }
        self.totalCount = total
        remainingCount = hasMore ? total - self.badges.count : 0
    }
}

public enum ProfileBadgePresentation {
    public static func unique(_ badges: [Badge]) -> [Badge] {
        var seen = Set<Int>()
        return badges.filter { $0.id > 0 && seen.insert($0.id).inserted }
    }

    public static func recentIDs(_ ids: [Int]) -> [Int] {
        ProfileEditorRules.recentBadgeIDs(adding: 0, to: ids)
    }

    /// The HTTP query is CSV, even though the local cache stores badge objects.
    public static func recentQuery(_ ids: [Int]) -> String {
        recentIDs(ids).map(String.init).joined(separator: ",")
    }

    /// An explicit showcase list also clears stale pins after an unpin. If the
    /// list is absent, preserve the badge's own server-provided marker.
    public static func decorated(_ badge: Badge, in response: ProfileBadgeSectionsResponse) -> Badge {
        var current = badge
        if let showcased = response.showcased {
            current.isShowcased = showcased.contains { $0.id == badge.id }
        }
        if let profile = response.profile {
            current.isSelected = profile.selectedBadge?.id == badge.id
        }
        return current
    }

    /// A showcase may carry only an ID while its category/preview has the full
    /// artwork. Fill absent fields without overriding explicit server values.
    public static func resolved(_ fallback: Badge, in response: ProfileBadgeSectionsResponse) -> Badge {
        let sources = (response.showcased ?? []) + (response.recent ?? [])
            + [response.profile?.selectedBadge].compactMap { $0 }
            + (response.sections ?? []).flatMap { $0.content ?? [] }
        var current = fallback
        for source in sources.reversed() where source.id == fallback.id {
            current = merging(source, fallback: current)
        }
        return decorated(current, in: response)
    }

    private static func merging(_ badge: Badge, fallback: Badge) -> Badge {
        var current = badge
        current.award = current.award ?? fallback.award
        current.badgeUrl = current.badgeUrl ?? fallback.badgeUrl
        current.category = current.category ?? fallback.category
        current.description = current.description ?? fallback.description
        current.imageMediumUrl = current.imageMediumUrl ?? fallback.imageMediumUrl
        current.imageSmallUrl = current.imageSmallUrl ?? fallback.imageSmallUrl
        current.name = current.name ?? fallback.name
        current.ownershipPercentage = current.ownershipPercentage ?? fallback.ownershipPercentage
        current.rarity = current.rarity ?? fallback.rarity
        current.timestamp = current.timestamp ?? fallback.timestamp
        current.type = current.type ?? fallback.type
        current.isAvailable = current.isAvailable ?? fallback.isAvailable
        current.isOwned = current.isOwned ?? fallback.isOwned
        current.isSelected = current.isSelected ?? fallback.isSelected
        current.isShowcased = current.isShowcased ?? fallback.isShowcased
        return current
    }

    /// Refresh cached entries by ID using fresh server objects, keep the selected
    /// badge first, discard missing entries, deduplicate and retain at most four.
    public static func recent(previousIDs: [Int], response: ProfileBadgeSectionsResponse) -> [Badge] {
        let fresh = Dictionary((response.recent ?? []).filter { $0.id > 0 }.map { ($0.id, $0) },
                               uniquingKeysWith: { _, latest in latest })
        let selected = response.profile?.selectedBadge.flatMap { badge in
            fresh[badge.id]
                ?? (response.sections ?? []).flatMap { $0.content ?? [] }.first { $0.id == badge.id }
                ?? badge
        }
        let previous = recentIDs(previousIDs).compactMap { fresh[$0] }
        return Array(unique([selected].compactMap { $0 } + previous)
            .prefix(ProfileEditorRules.recentBadgeLimit))
            .map {
                // Recent entries can be ID-only. Keep their explicit, latest
                // fields, while filling absent artwork from the same snapshot.
                decorated(merging($0, fallback: resolved($0, in: response)), in: response)
            }
    }
}

extension Badge {
    /// Android's nonzero type uses Lottie JSON, not an animated avatar/GIF.
    public var isAnimated: Bool { (type ?? 0) != 0 }

    public var artworkURL: URL? {
        for value in [imageMediumUrl, badgeUrl, imageSmallUrl] {
            guard let url = AnixartURL.image(value), let scheme = url.scheme?.lowercased(),
                  ["https", "http"].contains(scheme), url.host != nil else { continue }
            return url
        }
        return nil
    }
}

extension Profile {
    /// Some profile payloads supply only the flat badge_* fields. They describe
    /// the installed nickname badge, never proof of showcase pinning.
    public var selectedBadge: Badge? {
        let nested = badge.flatMap { $0.id > 0 ? $0 : nil }
        guard let id = nested?.id ?? badgeId, id > 0 else { return nil }
        var selected = nested ?? Badge(id: id)
        // Never attach flat artwork belonging to a different badge identity.
        if badgeId == nil || badgeId == id {
            selected.name = selected.name ?? badgeName
            selected.type = selected.type ?? badgeType
            selected.badgeUrl = selected.badgeUrl ?? badgeUrl
        }
        selected.isSelected = true
        return selected
    }
}
