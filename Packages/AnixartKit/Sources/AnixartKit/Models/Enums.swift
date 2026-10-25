import Foundation

/// The five watch lists, as used in `profile/list/all/{status}/{page}`.
/// Values confirmed against `DataPreferenceFragment` in the APK.
public enum ProfileListStatus: Int, Codable, CaseIterable, Sendable, Identifiable {
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
public enum BookmarkSort: Int, Codable, CaseIterable, Sendable, Identifiable {
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
public enum CatalogSort: Int, Codable, CaseIterable, Sendable, Identifiable {
    case dateUpdateDescending = 0
    case gradeDescending = 1
    case yearDescending = 2
    case popularDescending = 3
    case dateUpdateAscending = 4
    case gradeAscending = 5
    case yearAscending = 6
    case popularAscending = 7

    public var id: Int { rawValue }

    /// Order the filter UI lists these in (`arrays.xml`, `sort`): paired by key rather
    /// than by raw value, which is the order `allCases` would give.
    public static let displayOrder: [CatalogSort] = [
        .dateUpdateDescending, .dateUpdateAscending,
        .gradeDescending, .gradeAscending,
        .yearDescending, .yearAscending,
        .popularDescending, .popularAscending
    ]

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
public enum GenresMode: Int, Codable, CaseIterable, Sendable {
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

/// Episode-count presets, as the filter UI offers them.
///
/// The preset index is **not** what goes on the wire: `CustomFilterTabPresenter`
/// resolves it into an explicit `episodes_from` / `episodes_to` pair, which is what
/// `range` returns here. Labels and bounds are from `arrays.xml` (`episodes`).
public enum EpisodeCountPreset: Int, Codable, CaseIterable, Sendable, Identifiable {
    case from1to12 = 1
    case from13to25 = 2
    case from26to100 = 3
    case over100 = 4

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .from1to12: return "От 1 до 12"
        case .from13to25: return "От 13 до 25"
        case .from26to100: return "От 26 до 100"
        case .over100: return "Больше 100"
        }
    }

    /// `to` is absent for the open-ended preset, matching the Android client.
    public var range: (from: Int?, to: Int?) {
        switch self {
        case .from1to12: return (1, 12)
        case .from13to25: return (13, 25)
        case .from26to100: return (26, 100)
        case .over100: return (100, nil)
        }
    }
}

/// Episode-length presets. Same story: resolved into a minute range, not sent as an index.
public enum EpisodeDurationPreset: Int, Codable, CaseIterable, Sendable, Identifiable {
    case upTo10 = 1
    case upTo30 = 2
    case over30 = 3

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .upTo10: return "До 10 минут"
        case .upTo30: return "До 30 минут"
        case .over30: return "Более 30 минут"
        }
    }

    public var range: (from: Int?, to: Int?) {
        switch self {
        case .upTo10: return (1, 10)
        case .upTo30: return (11, 30)
        case .over30: return (31, nil)
        }
    }
}

/// `category_id`. Values and labels from `arrays.xml` (`categories`).
public enum ReleaseCategory: Int, Codable, CaseIterable, Sendable, Identifiable {
    case series = 1
    case movie = 2
    case ova = 3
    case dorama = 4

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .series: return "Сериал"
        case .movie: return "Полнометражный фильм"
        case .ova: return "OVA"
        case .dorama: return "Дорама"
        }
    }
}

/// `status_id`. Values and labels from `arrays.xml` (`statuses`).
///
/// Note the wording: "Вышел" means finished airing, "Выходит" means currently airing.
public enum AiringStatus: Int, Codable, CaseIterable, Sendable, Identifiable {
    case released = 1
    case ongoing = 2
    case announced = 3

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .released: return "Вышел"
        case .ongoing: return "Выходит"
        case .announced: return "Анонс"
        }
    }
}

/// `source` in the filter body -- the work the release is adapted from. Sent as the
/// label itself, not an id. List from `arrays.xml` (`sources`).
public enum SourceMaterial: String, Codable, CaseIterable, Sendable, Identifiable {
    case original = "Оригинал"
    case manga = "Манга"
    case webManga = "Веб-манга"
    case yonkoma = "Енкома"
    case ranobe = "Ранобэ"
    case novel = "Новелла"
    case webNovel = "Веб-новелла"
    case game = "Игра"
    case visualNovel = "Визуальная новелла"
    case cardGame = "Карточная игра"
    case book = "Книга"
    case pictureBook = "Книга с картинками"
    case music = "Музыка"
    case radio = "Радио"
    case moreThanOne = "Более одного"
    case other = "Другое"

    public var id: String { rawValue }
    public var title: String { rawValue }
}

/// `season` in the filter body and on `Release`.
public enum ReleaseSeason: Int, Codable, CaseIterable, Sendable, Identifiable {
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
public enum SearchScope: Int, Codable, CaseIterable, Sendable {
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
public enum ReleaseVote: Int, Codable, CaseIterable, Sendable, Identifiable {
    case one = 1, two = 2, three = 3, four = 4, five = 5
    public var id: Int { rawValue }
}
