import Foundation

extension Release {
    public var shareURL: URL {
        AnixartEnvironment.webBaseURL.appendingPathComponent("release/\(id)")
    }

    public var statusBadgeText: String? {
        if let name = status?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        return statusId.flatMap(AiringStatus.init(rawValue:))?.title
    }

    public var categoryBadgeText: String? {
        guard let name = category?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return name
    }

    /// Unknown countries remain readable without assigning an invented flag.
    public var countryFlag: String? {
        guard let country = country?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }
        switch country {
        case "япония", "japan", "jp": return "🇯🇵"
        case "китай", "china", "cn": return "🇨🇳"
        case "южная корея", "корея", "south korea", "kr": return "🇰🇷"
        case "сша", "соединённые штаты", "united states", "us": return "🇺🇸"
        case "россия", "russia", "ru": return "🇷🇺"
        case "тайвань", "taiwan", "tw": return "🇹🇼"
        case "гонконг", "hong kong", "hk": return "🇭🇰"
        case "франция", "france", "fr": return "🇫🇷"
        default: return nil
        }
    }

    private var uniqueRelatedReleases: [Release] {
        var seen = Set<Int>()
        return (relatedReleases ?? []).filter { seen.insert($0.id).inserted }
    }

    public var relatedPreviewReleases: [Release] { Array(uniqueRelatedReleases.prefix(3)) }

    /// Do not navigate to the same three titles when the whole franchise is visible.
    public var hasMoreRelatedReleases: Bool {
        guard related != nil else { return false }
        let loaded = uniqueRelatedReleases.count
        let total = [relatedCount, related?.releaseCount].compactMap { $0 }.filter { $0 >= 0 }.max()
        if let total { return max(total, loaded) > min(loaded, 3) }
        // Sparse responses must still provide a way to fetch the franchise.
        return loaded == 0 || loaded >= 3
    }
}
