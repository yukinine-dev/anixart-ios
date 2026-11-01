import Foundation
import AnixartKit

/// The tabs across the top of the Главная screen.
///
/// Each preset is a `filter/{page}` query with one constraint, taken verbatim from
/// `HomeFragment` in the APK: Аниме and Дунхуа filter by country, Онгоинги / Анонсы /
/// Завершенные by `status_id`, Фильмы and OVA by `category_id`, and Последнее applies
/// nothing at all. None of them touch the sort, so it stays at `FilterRequest`'s own
/// default of 0 -- recently added and updated first -- which is what makes Последнее
/// a "latest" tab.
enum HomeTab: Hashable, Identifiable, CaseIterable {
    /// The user's own filter, stored on the device. Always first.
    case custom
    case anime
    case donghua
    case latest
    case ongoing
    case announced
    case finished
    case movies
    case ova

    var id: Self { self }

    static let allCases: [HomeTab] = [
        .custom, .anime, .donghua, .latest, .ongoing, .announced, .finished, .movies, .ova
    ]

    /// Default title. `custom` can be renamed, so the view falls back to this only when
    /// the stored name is empty -- the same rule `HomeFragment` applies.
    var title: String {
        switch self {
        case .custom: return "Моя вкладка"
        case .anime: return "Аниме"
        case .donghua: return "Дунхуа"
        case .latest: return "Последнее"
        case .ongoing: return "Онгоинги"
        case .announced: return "Анонсы"
        case .finished: return "Завершенные"
        case .movies: return "Фильмы"
        case .ova: return "OVA"
        }
    }

    /// Confirmed on the original phone's default-tab dialog, 2 Nov 2026.
    var summary: String {
        switch self {
        case .custom: return "Персонально настроенный раздел"
        case .anime: return "Японская анимация"
        case .donghua: return "Китайская анимация"
        case .latest: return "Недавно добавленные и обновленные релизы"
        case .ongoing: return "Сериалы, которые выходят сейчас"
        case .announced: return "Будущие релизы и новинки"
        case .finished: return "Полностью вышедшие релизы"
        case .movies: return "Полнометражные анимационные фильмы"
        case .ova: return "Специальные и дополнительные эпизоды"
        }
    }

    /// The filter this tab sends, or `nil` for the custom tab, which builds its own.
    var filter: FilterRequest? {
        switch self {
        case .custom:
            return nil
        case .anime:
            return FilterRequest(country: "Япония")
        case .donghua:
            return FilterRequest(country: "Китай")
        case .latest:
            return FilterRequest()
        case .ongoing:
            return FilterRequest(status: .ongoing)
        case .announced:
            return FilterRequest(status: .announced)
        case .finished:
            return FilterRequest(status: .released)
        case .movies:
            return FilterRequest(category: .movie)
        case .ova:
            return FilterRequest(category: .ova)
        }
    }
}
