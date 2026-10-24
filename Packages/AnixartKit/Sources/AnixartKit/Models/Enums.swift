import Foundation

/// The five watch lists, as used in `profile/list/all/{status}/{page}`.
/// Values confirmed against `DataPreferenceFragment` in the APK.
public enum ProfileListStatus: Int, CaseIterable, Sendable, Identifiable {
    case watching = 1
    case plan = 2
    case completed = 3
    case holdOn = 4
    case dropped = 5

    public var id: Int { rawValue }

    /// Label as the Android app shows it (`list_*` strings).
    public var title: String {
        switch self {
        case .watching: return "Смотрю"
        case .plan: return "В планах"
        case .completed: return "Просмотрено"
        case .holdOn: return "Отложено"
        case .dropped: return "Брошено"
        }
    }

    public var systemImage: String {
        switch self {
        case .watching: return "play.circle"
        case .plan: return "clock"
        case .completed: return "checkmark.circle"
        case .holdOn: return "pause.circle"
        case .dropped: return "xmark.circle"
        }
    }
}

/// `sort` for `favorite/all` and `profile/list/all`.
/// Values confirmed against `ExtraBookmarksModel` in the APK (1-based, 1 is the default).
public enum BookmarkSort: Int, CaseIterable, Sendable, Identifiable {
    case addedDescending = 1
    case addedAscending = 2
    case releaseDateDescending = 3
    case releaseDateAscending = 4
    case titleDescending = 5
    case titleAscending = 6
    case ratingDescending = 7
    case ratingAscending = 8

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .addedDescending: return "По добавлению: от новых к старым"
        case .addedAscending: return "По добавлению: от старых к новым"
        case .releaseDateDescending: return "По дате выхода: сначала новые"
        case .releaseDateAscending: return "По дате выхода: сначала старые"
        case .titleDescending: return "По названию: Я–А"
        case .titleAscending: return "По названию: А–Я"
        case .ratingDescending: return "По рейтингу: сначала высокий"
        case .ratingAscending: return "По рейтингу: сначала низкий"
        }
    }
}

/// `sort` inside the catalogue filter body. Values from `FilterRequest` in the APK.
public enum CatalogSort: Int, CaseIterable, Sendable, Identifiable {
    case dateUpdateDescending = 0
    case gradeDescending = 1
    case yearDescending = 2
    case popularDescending = 3
    case dateUpdateAscending = 4
    case gradeAscending = 5
    case yearAscending = 6
    case popularAscending = 7

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .dateUpdateDescending: return "Сначала недавно обновлённое"
        case .dateUpdateAscending: return "Сначала давно обновлённое"
        case .gradeDescending: return "Сначала с высоким рейтингом"
        case .gradeAscending: return "Сначала с низким рейтингом"
        case .yearDescending: return "Сначала новые по году выхода"
        case .yearAscending: return "Сначала старые по году выхода"
        case .popularDescending: return "Сначала самые популярные"
        case .popularAscending: return "Сначала наименее популярные"
        }
    }
}

/// `genres_mode` in the filter body. Values from `FilterRequest`.
public enum GenresMode: Int, CaseIterable, Sendable {
    case all = 0
    case any = 1
    case exclude = 2

    public var title: String {
        switch self {
        case .all: return "Все выбранные жанры"
        case .any: return "Любой из выбранных"
        case .exclude: return "Исключить выбранные"
        }
    }
}

/// `episodes_from` / `episodes_to` presets from `FilterRequest`.
public enum EpisodeCountPreset: Int, CaseIterable, Sendable {
    case lessThan13 = 1
    case moreThan13 = 2
    case moreThan26 = 3
    case moreThan100 = 4

    public var title: String {
        switch self {
        case .lessThan13: return "менее 13"
        case .moreThan13: return "от 13"
        case .moreThan26: return "от 26"
        case .moreThan100: return "от 100"
        }
    }
}

/// `season` in the filter body and on `Release`.
public enum ReleaseSeason: Int, CaseIterable, Sendable, Identifiable {
    case winter = 1
    case spring = 2
    case summer = 3
    case autumn = 4

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .winter: return "зима"
        case .spring: return "весна"
        case .summer: return "лето"
        case .autumn: return "осень"
        }
    }
}

/// `searchBy` in a `SearchRequest` body. `0` searches every title field, which is
/// the default the Android client sends.
public enum SearchScope: Int, CaseIterable, Sendable {
    case all = 0
    case titleRu = 1
    case titleOriginal = 2
    case titleAlt = 3

    public var title: String {
        switch self {
        case .all: return "По всем названиям"
        case .titleRu: return "По русскому названию"
        case .titleOriginal: return "По оригинальному названию"
        case .titleAlt: return "По альтернативным названиям"
        }
    }
}

/// A user's score for a release, `release/vote/add/{id}/{vote}`.
public enum ReleaseVote: Int, CaseIterable, Sendable, Identifiable {
    case one = 1, two = 2, three = 3, four = 4, five = 5
    public var id: Int { rawValue }
}
