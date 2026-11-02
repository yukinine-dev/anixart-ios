import Foundation
import AnixartKit

/// Values behind the fourteen collapsed controls in the original full filter.
/// Only Apply exports a request; UI preset indices never go onto the wire.
@MainActor
@Observable
final class CatalogFilterDraft {
    var request: FilterRequest

    init(_ current: FilterRequest) { request = current.normalized }

    var filter: FilterRequest { request.normalized }
    var validationMessage: String? { request.validationMessage }

    var sort: CatalogSort {
        get { CatalogSort(rawValue: request.sort ?? 0) ?? .dateUpdateDescending }
        set { request.sort = newValue.rawValue }
    }

    var category: ReleaseCategory? {
        get { request.categoryId.flatMap(ReleaseCategory.init(rawValue:)) }
        set { request.categoryId = newValue?.rawValue }
    }

    var source: SourceMaterial? {
        get { request.source.flatMap(SourceMaterial.init(rawValue:)) }
        set { request.source = newValue?.rawValue }
    }

    var season: ReleaseSeason? {
        get { request.season.flatMap(ReleaseSeason.init(rawValue:)) }
        set { request.season = newValue?.rawValue }
    }

    var status: AiringStatus? {
        get { request.statusId.flatMap(AiringStatus.init(rawValue:)) }
        set { request.statusId = newValue?.rawValue }
    }

    var episodes: EpisodeCountPreset? {
        get {
            EpisodeCountPreset.allCases.first {
                $0.range.from == request.episodesFrom && $0.range.to == request.episodesTo
            }
        }
        set { request.episodesFrom = newValue?.range.from; request.episodesTo = newValue?.range.to }
    }

    var episodeDuration: EpisodeDurationPreset? {
        get {
            EpisodeDurationPreset.allCases.first {
                $0.range.from == request.episodeDurationFrom && $0.range.to == request.episodeDurationTo
            }
        }
        set { request.episodeDurationFrom = newValue?.range.from; request.episodeDurationTo = newValue?.range.to }
    }

    var genres: [String] {
        get { request.genres ?? [] }
        set {
            let mode = genreMode
            request.genres = newValue.isEmpty ? nil : newValue
            if newValue.isEmpty {
                request.genresMode = nil
                request.isGenresExcludeModeEnabled = nil
            } else { genreMode = mode }
        }
    }

    var genreMode: GenresMode {
        get {
            if request.isGenresExcludeModeEnabled == true { return .exclude }
            return request.genresMode.flatMap(GenresMode.init(rawValue:)) ?? .any
        }
        set {
            request.genresMode = newValue.rawValue
            request.isGenresExcludeModeEnabled = newValue == .exclude ? true : nil
        }
    }

    var excludedLists: [ProfileListStatus] {
        get { (request.profileListExclusions ?? []).compactMap(ProfileListStatus.init(rawValue:)) }
        set { request.profileListExclusions = newValue.isEmpty ? nil : newValue.map(\.rawValue) }
    }

    var typeIDs: [Int] {
        get { request.types ?? [] }
        set { request.types = newValue.isEmpty ? nil : newValue }
    }

    var ageRatings: [Int] {
        get { request.ageRatings ?? [] }
        set { request.ageRatings = newValue.isEmpty ? nil : newValue }
    }

    var yearsSummary: String? {
        switch (request.startYear, request.endYear) {
        case (let start?, let end?) where start == end: return String(start)
        case (let start?, let end?): return "\(start)–\(end)"
        case (let start?, nil): return "с \(start)"
        case (nil, let end?): return "до \(end)"
        case (nil, nil): return nil
        }
    }

    func reset() { request = FilterRequest() }
}
