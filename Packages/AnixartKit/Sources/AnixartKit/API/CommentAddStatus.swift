import Foundation

/// CommentAddResponse codes belong to text submission, not comment voting or login.
enum CommentAddStatus {
    static let embeddableNotFound = 2
    static let commentNotFound = 3
    static let profileNotFound = 4
    static let commentIsTooShort = 5
    static let commentIsTooLong = 6
    static let commentLimitReached = 7
    static let inBlocklist = 8

    static func message(code: Int, path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count == 4, let category = ProfileCommentCategory(rawValue: String(parts[0])),
              parts[1] == "comment", parts[2] == "add" else { return nil }
        switch code {
        case embeddableNotFound:
            switch category {
            case .releases: return "Вы не можете комментировать этот релиз, поскольку он был удалён."
            case .collections: return "Вы не можете комментировать эту коллекцию, поскольку она была удалена."
            case .articles: return "Вы не можете комментировать эту запись, поскольку она была удалена."
            }
        case commentNotFound:
            return "Комментарий, на который вы отвечаете, не найден."
        case profileNotFound:
            return "Пользователь, которому вы отвечаете, не найден."
        case commentIsTooShort:
            return "Ваш комментарий слишком короткий. Дайте свободу мысли!"
        case commentIsTooLong:
            return "Ваш комментарий слишком длинный. Краткость – сестра таланта!"
        case commentLimitReached:
            return "Вы превысили допустимый лимит по комментариям за сутки. Попробуйте оставить комментарий позже."
        case inBlocklist:
            return "Пользователь внёс Вас в свой блоклист. Вы не можете отвечать на его комментарии."
        default:
            // Real 402 / 403 remain the shared account-ban errors.
            return nil
        }
    }
}
