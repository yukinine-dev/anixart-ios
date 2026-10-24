import Foundation

public enum AnixartError: Error, Sendable, Equatable {
    /// Transport failure before a response arrived.
    case transport(message: String, isOffline: Bool)
    /// Non-2xx HTTP status.
    case http(statusCode: Int, path: String)
    /// HTTP 200, but the body's `code` field was not `0`.
    case api(code: Int, path: String)
    /// The body did not match the expected shape.
    case decoding(message: String, path: String)
    /// The endpoint needs a session token and none was stored.
    case notAuthenticated(path: String)
    /// The path and query could not be turned into a URL.
    case invalidURL(path: String)

    /// True when the account is banned and the action keeps failing until the ban lifts.
    public var isBan: Bool {
        if case .api(let code, _) = self {
            return code == AnixartStatus.banned || code == AnixartStatus.permBanned
        }
        return false
    }

    /// True when retrying the same request could plausibly succeed.
    public var isRetryable: Bool {
        switch self {
        case .transport: return true
        case .http(let status, _): return status >= 500 || status == 429
        default: return false
        }
    }

    static func wrapping(transportError error: any Error) -> AnixartError {
        let urlError = error as? URLError
        let offline: Bool
        switch urlError?.code {
        case .notConnectedToInternet?, .networkConnectionLost?, .dataNotAllowed?:
            offline = true
        default:
            offline = false
        }
        return .transport(message: error.localizedDescription, isOffline: offline)
    }
}

extension AnixartError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .transport(let message, let isOffline):
            return isOffline ? "Нет подключения к интернету" : "Нет соединения с сервером: \(message)"
        case .http(let status, let path):
            return "Сервер вернул HTTP \(status) для \(path)"
        case .api(let code, let path):
            switch code {
            case AnixartStatus.banned: return "Действие недоступно: аккаунт заблокирован"
            case AnixartStatus.permBanned: return "Действие недоступно: аккаунт заблокирован навсегда"
            case AnixartStatus.invalidLogin: return "Неверный никнейм или email"
            case AnixartStatus.invalidPassword: return "Неверный пароль"
            default: return "Сервер отклонил запрос \(path) (код \(code))"
            }
        case .decoding(_, let path):
            return "Не удалось разобрать ответ сервера для \(path)"
        case .notAuthenticated:
            return "Нужно войти в аккаунт"
        case .invalidURL(let path):
            return "Некорректный адрес запроса: \(path)"
        }
    }
}
