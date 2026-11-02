import Foundation

/// Comment arrows send `1` / `2`, not a signed score or the desired stored state.
/// Repeating the same value removes the vote on the server. `0` only appears in
/// the returned comment's `vote` field when the viewer has not voted.
public enum CommentVote: Int, Codable, CaseIterable, Sendable {
    case negative = 1
    case positive = 2

    public func isSelected(currentVote: Int?) -> Bool {
        currentVote == rawValue
    }
}

/// Mirrors CommentVoteResponse and the CommentsPresenter / CommentRepliesPresenter
/// callbacks in the reference APK. These codes are not auth/signIn errors.
enum CommentVoteStatus {
    static let negativeVoteLimitReached = 2
    static let insufficientAccountAge = 3

    static func message(code: Int, path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count == 5, ProfileCommentCategory(rawValue: String(parts[0])) != nil,
              parts[1] == "comment", parts[2] == "vote" else { return nil }
        switch code {
        case negativeVoteLimitReached:
            return "Вы превысили дневной лимит на отрицательные оценки"
        case insufficientAccountAge:
            return "Кажется, Вы зарегистрированы совсем недавно. Побудьте с нами немного дольше, чтобы получить возможность ставить оценки."
        case AnixartStatus.banned:
            return "Вы не можете голосовать, поскольку ваш аккаунт заблокирован"
        case AnixartStatus.permBanned:
            return "Вы не можете голосовать, поскольку ваш аккаунт заблокирован навсегда"
        default:
            return "Сервер отклонил запрос \(path) (код \(code))"
        }
    }
}
