import Foundation

extension Release {
    /// Title to show in lists, preferring the Russian title as the Android app does.
    public var displayTitle: String {
        let candidates = [titleRu, titleOriginal, titleAlt]
        return candidates.compactMap { $0 }.first { !$0.isEmpty } ?? "Без названия"
    }

    /// Secondary title, shown under `displayTitle` when it adds information.
    public var displaySubtitle: String? {
        guard let original = titleOriginal, !original.isEmpty, original != displayTitle else { return nil }
        return original
    }

    public var posterURL: URL? { AnixartURL.image(image) }

    public var screenshotURLs: [URL] {
        (screenshotImages ?? []).compactMap { AnixartURL.image($0) }
    }

    /// `genres` arrives as one comma-separated string, not an array.
    public var genreList: [String] {
        (genres ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Rating out of 5, or `nil` when the server withholds it for want of votes.
    public var ratingValue: Double? {
        guard let grade, grade > 0 else { return nil }
        return grade
    }

    public var ratingText: String? {
        ratingValue.map { String(format: "%.1f", $0) }
    }

    /// `3 из 12` style episode counter, or just the released count when the total is unknown.
    public var episodeProgressText: String? {
        switch (episodesReleased, episodesTotal) {
        case (let released?, let total?) where total > 0:
            return "\(released) из \(total)"
        case (let released?, _) where released > 0:
            return "\(released) эп."
        case (_, let total?) where total > 0:
            return "\(total) эп."
        default:
            return nil
        }
    }

    public var seasonAndYear: String? {
        let seasonName = season.flatMap { ReleaseSeason(rawValue: $0)?.title }
        switch (seasonName, year) {
        case (let s?, let y?) where !y.isEmpty: return "\(s) \(y)"
        case (_, let y?) where !y.isEmpty: return y
        case (let s?, _): return s
        default: return nil
        }
    }

    /// Russian age label, from the `ageRatings` array in the APK (index 0...4).
    public var ageRatingText: String? {
        let labels = ["0+", "6+", "12+", "16+", "18+"]
        guard let ageRating, labels.indices.contains(ageRating) else { return nil }
        return labels[ageRating]
    }

    public var listStatus: ProfileListStatus? {
        profileListStatus.flatMap(ProfileListStatus.init(rawValue:))
    }

    public var isInAnyList: Bool { listStatus != nil || (isFavorite ?? false) }

    /// True when playback is unavailable -- removed, geo-blocked, or disabled upstream.
    public var isPlaybackUnavailable: Bool {
        (isPlayDisabled ?? false) || (isViewBlocked ?? false) || (isDeleted ?? false)
    }

    /// Reason to show in place of the play button.
    public var playbackBlockedReason: String? {
        if isDeleted ?? false { return "Релиз удалён" }
        if isRuBlocked ?? false { return "Недоступно в вашей стране" }
        if isViewBlocked ?? false { return "Просмотр недоступен" }
        if isPlayDisabled ?? false { return "Недоступно" }
        return nil
    }

    /// "Продолжить: Серия 4 (AniLibria)" for a release already in progress.
    public var continueWatchingText: String? {
        guard let episodeName = lastViewEpisodeName, !episodeName.isEmpty else { return nil }
        if let typeName = lastViewEpisodeTypeName, !typeName.isEmpty {
            return "\(episodeName) · \(typeName)"
        }
        return episodeName
    }

    public var lastViewedDate: Date? {
        guard let lastViewTimestamp, lastViewTimestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(lastViewTimestamp))
    }
}

extension EpisodeType {
    public var displayName: String { (name?.isEmpty == false ? name : nil) ?? "Без названия" }
    public var iconURL: URL? { AnixartURL.image(icon) }

    public var episodeCountText: String? {
        guard let episodesCount, episodesCount > 0 else { return nil }
        return "\(episodesCount) эп."
    }
}

extension EpisodeSource {
    public var displayName: String { (name?.isEmpty == false ? name : nil) ?? "Источник" }
}

extension Episode {
    public var displayName: String {
        if let name, !name.isEmpty { return name }
        if let position { return "Серия \(position)" }
        return "Серия"
    }

    /// `true` when the episode is an embeddable player page rather than a direct
    /// video file, which decides whether it goes to `AVPlayer` or a web view.
    public var isEmbed: Bool { iframe ?? false }

    public var playbackURL: URL? {
        guard let url, !url.isEmpty else { return nil }
        return URL(string: url)
    }

    public var resumePosition: TimeInterval? {
        guard let playbackPosition, playbackPosition > 0 else { return nil }
        // The Android player stores this in milliseconds.
        return TimeInterval(playbackPosition) / 1000
    }
}

extension Profile {
    public var displayLogin: String { (login?.isEmpty == false ? login : nil) ?? "Профиль" }
    public var avatarURL: URL? { AnixartURL.image(avatar) }

    public var isCurrentlyBanned: Bool {
        (isPermBanned ?? false) || (isBanned ?? false)
    }

    public func listCount(for status: ProfileListStatus) -> Int {
        switch status {
        case .watching: return watchingCount ?? 0
        case .plan: return planCount ?? 0
        case .completed: return completedCount ?? 0
        case .holdOn: return holdOnCount ?? 0
        case .dropped: return droppedCount ?? 0
        }
    }
}

extension ReleaseCollection {
    public var displayTitle: String { (title?.isEmpty == false ? title : nil) ?? "Коллекция" }
    public var coverURL: URL? { AnixartURL.image(image) }
}

extension ReleaseComment {
    public var authorLogin: String { profile?.login ?? "Пользователь" }
    public var authorAvatarURL: URL? { AnixartURL.image(profile?.avatar) }
    public var postedAt: Date? {
        guard let timestamp, timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
    public var containsSpoiler: Bool { isSpoiler ?? false }
}

extension ScheduleResponse {
    /// Weekday-ordered schedule, Monday first, as the Android app lays it out.
    public var byWeekday: [(title: String, releases: [Release])] {
        [
            ("Понедельник", monday ?? []),
            ("Вторник", tuesday ?? []),
            ("Среда", wednesday ?? []),
            ("Четверг", thursday ?? []),
            ("Пятница", friday ?? []),
            ("Суббота", saturday ?? []),
            ("Воскресенье", sunday ?? [])
        ]
    }
}
