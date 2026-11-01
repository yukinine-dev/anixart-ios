import Foundation

/// IDs from the Android profile section picker; these are not watch-list IDs.
public enum ProfileSection: Int, Codable, CaseIterable, Sendable, Identifiable {
    case statistics = 0, votes, collections, comments, videos, badges

    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .statistics: return "Статистика"
        case .votes: return "Оценки релизов"
        case .collections: return "Коллекции"
        case .comments: return "Комментарии"
        case .videos: return "Видео"
        case .badges: return "Значки"
        }
    }
    public var systemImage: String {
        switch self {
        case .statistics: return "chart.bar.fill"
        case .votes: return "star"
        case .collections: return "square.on.square"
        case .comments: return "bubble.left"
        case .videos: return "play.rectangle"
        case .badges: return "seal"
        }
    }
}

public enum ProfilePrivacy: Int, Codable, CaseIterable, Sendable, Identifiable {
    case everyone = 0, friends, onlyMe
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .everyone: return "Все пользователи"
        case .friends: return "Только друзья"
        case .onlyMe: return "Только я"
        }
    }
}

public enum FriendRequestPrivacy: Int, Codable, CaseIterable, Sendable, Identifiable {
    case everyone = 0, nobody
    public var id: Int { rawValue }
    public var title: String { self == .everyone ? "Все пользователи" : "Никто" }
}

/// The vote menu uses a one-based sort, including the five star filters.
public enum ProfileVoteSort: Int, Codable, CaseIterable, Sendable, Identifiable {
    case newest = 1, oldest, fiveStars, fourStars, threeStars, twoStars, oneStar
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .newest: return "Сначала последние"
        case .oldest: return "Сначала старые"
        case .fiveStars: return "5 звёзд"
        case .fourStars: return "4 звезды"
        case .threeStars: return "3 звезды"
        case .twoStars: return "2 звезды"
        case .oneStar: return "1 звезда"
        }
    }
}

public enum ProfileEditorRules {
    public static let statusLimit = 80
    public static let loginLength = 3...20
    public static let showcaseLimit = 3
    public static let recentBadgeLimit = 4
    public static let minimumCoverReputation = 3
    public static let passwordLimit = 32
    public static let avatarAnimationByteLimit = 4 * 1024 * 1024
    public static let badgePreviewLimit = 7
    public static let categoryBadgePreviewLimit = 11

    /// Android's String.length/InputFilter counts UTF-16 code units, not graphemes.
    public static func isValidStatus(_ value: String) -> Bool { value.utf16.count <= statusLimit }
    public static func isValidLoginLength(_ value: String) -> Bool { loginLength.contains(value.utf16.count) }

    /// Email verification takes a Java int, not a string or a Unicode digit.
    public static func emailVerificationCode(_ input: String) -> Int? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let code = Int(value), code <= Int(Int32.max) else { return nil }
        return code
    }

    public static func recentBadgeIDs(adding id: Int, to previous: [Int]) -> [Int] {
        var seen = Set<Int>()
        return Array(([id] + previous).filter { $0 > 0 && seen.insert($0).inserted }.prefix(recentBadgeLimit))
    }

    /// Truncates without splitting a surrogate pair or a composed character.
    public static func limitedStatus(_ value: String) -> String {
        limitedText(value, utf16Limit: statusLimit)
    }

    public static func limitedText(_ value: String, utf16Limit: Int) -> String {
        var result = ""
        var count = 0
        for character in value {
            let length = String(character).utf16.count
            guard count + length <= utf16Limit else { break }
            result.append(character)
            count += length
        }
        return result
    }
}

extension ProfilePreferenceResponse {
    public func isBound(to service: ProfilePreferenceEndpoints.Service) -> Bool? {
        switch service {
        case .yandex: return isYandexBound
        case .vk: return isVkBound
        case .telegram: return isTelegramBound
        case .google: return isGoogleBound
        }
    }
}

public struct ProfileStatusEditRequest: Codable, Hashable, Sendable {
    public var status: String
    public init(status: String) { self.status = status }
}

public struct ProfileIDRequest: Codable, Hashable, Sendable {
    public var id: Int
    public init(id: Int) { self.id = id }
}

public struct PrivacyEditRequest: Codable, Hashable, Sendable {
    public var permission: Int
    public init(permission: Int) { self.permission = permission }
}

public struct BadgeReorderRequest: Codable, Hashable, Sendable {
    public var ids: [Int]
    public init(ids: [Int]) { self.ids = ids }
}

/// Deliberately camelCase, unlike the social response's snake_case keys.
public struct SocialPagesEditRequest: Codable, Hashable, Sendable {
    public var vkPage: String
    public var tgPage: String
    public var instPage: String
    public var ttPage: String
    public var discordPage: String

    public init(vkPage: String = "", tgPage: String = "", instPage: String = "", ttPage: String = "", discordPage: String = "") {
        self.vkPage = vkPage
        self.tgPage = tgPage
        self.instPage = instPage
        self.ttPage = ttPage
        self.discordPage = discordPage
    }

    public init(_ response: ProfileSocialResponse) {
        self.init(vkPage: response.vkPage ?? "", tgPage: response.tgPage ?? "", instPage: response.instPage ?? "",
                  ttPage: response.ttPage ?? "", discordPage: response.discordPage ?? "")
    }
}
