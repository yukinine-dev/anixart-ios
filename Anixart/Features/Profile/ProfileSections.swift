import SwiftUI
import UIKit
import AnixartKit

struct ProfileEmptySection: View {
    var message = "Нет данных для отображения"

    var body: some View {
        Text(message)
            .font(.ax(.subheadline))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 36)
    }
}

@MainActor
struct ProfileSocialLinks: View {
    @Environment(\.openURL) private var openURL
    let profile: Profile
    @State private var copiedDiscord = false

    private var pages: [(name: String, icon: String, value: String)] {
        guard profile.isSocialHidden != true else { return [] }
        return [
            ("VK", "person.2", profile.vkPage),
            ("Telegram", "paperplane", profile.tgPage),
            ("Discord", "bubble.left.and.bubble.right", profile.discordPage),
            ("TikTok", "music.note", profile.ttPage)
        ].compactMap { name, icon, page in
            guard let page, !page.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (name, icon, page)
        }
    }

    var body: some View {
        ForEach(pages, id: \.name) { page in
            Button {
                if let url = ProfileSocialAddress.url(page.value, service: page.name) { openURL(url) }
                else if page.name == "Discord" {
                    UIPasteboard.general.string = page.value
                    copiedDiscord = true
                }
            } label: {
                Image(systemName: page.icon)
                    .font(.ax(.headline))
                    .frame(width: 48, height: 36)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(page.name)
        }
        .alert("Discord", isPresented: $copiedDiscord) {
            Button("Понятно", role: .cancel) { }
        } message: { Text("Имя пользователя скопировано") }
    }
}

enum ProfileSocialAddress {
    static func url(_ input: String, service: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let url = URL(string: value), let scheme = url.scheme {
            guard ["http", "https"].contains(scheme.lowercased()), url.host != nil else { return nil }
            return url
        }
        let name = value.hasPrefix("@") ? String(value.dropFirst()) : value
        let address: String
        if value.contains("/") || value.contains(".") { address = "https://\(value)" }
        else {
            switch service {
            case "VK": address = "https://vk.com/\(name)"
            case "Telegram": address = "https://t.me/\(name)"
            case "TikTok": address = "https://www.tiktok.com/@\(name)"
            default: return nil
            }
        }
        guard let url = URL(string: address), url.host != nil else { return nil }
        return url
    }
}

/// This block stays below every one of the six interchangeable sections.
@MainActor
struct ProfileActivitySection: View {
    let profile: Profile
    let viewer: ProfileViewerKey?
    @State private var showsHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            Divider().padding(.horizontal)
            SectionHeader(title: "Динамика просмотра серий")
            if let dynamics = profile.watchDynamics, !dynamics.isEmpty {
                ProfileWatchChart(points: dynamics)
            } else {
                ProfileEmptySection(message: "Данных о просмотрах пока нет")
            }
            Button("Узнать подробнее") { showsHelp = true }
                .font(.ax(.subheadline, .medium))
                .frame(maxWidth: .infinity)
            Divider().padding(.horizontal)
            SectionHeader(title: "Просмотрено недавно")
            if let history = profile.history, !history.isEmpty {
                ForEach(history) { release in
                    NavigationLink {
                        ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: viewer)
                    } label: {
                        HStack(spacing: 16) {
                            ReleasePoster(url: release.posterURL, width: 52)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(release.displayTitle).font(.ax(.subheadline)).foregroundStyle(.primary).lineLimit(2)
                                Text(historySubtitle(release)).font(.ax(.subheadline)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ProfileEmptySection(message: "История просмотра пуста")
            }
        }
        .padding(.top, Theme.Spacing.section)
        .sheet(isPresented: $showsHelp) {
            ProfileHelpSheet(title: "Динамика просмотра", paragraphs: [
                "Динамика просмотра серий за текущий день станет доступна только на следующий день."
            ])
        }
    }

    private func historySubtitle(_ release: Release) -> String {
        [release.lastViewEpisodeName, Format.relativeDate(release.lastViewedDate)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • ")
    }
}

struct ProfileWatchChart: View {
    let points: [ProfileWatchDynamics]
    private var maximum: Int { max(1, points.map { max(0, $0.count ?? 0) }.max() ?? 1) }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 16) {
                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        VStack(spacing: 8) {
                            VStack(spacing: 5) {
                                Spacer(minLength: 0)
                                Text("\(max(0, point.count ?? 0))")
                                    .font(.ax(.subheadline, .medium)).foregroundStyle(.secondary)
                                UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7)
                                    .fill(Color.primary.opacity(0.85))
                                    .frame(width: 22, height: max(8, 116 * CGFloat(max(0, point.count ?? 0)) / CGFloat(maximum)))
                            }
                            .frame(height: 146)
                            Text(dayLabel(point))
                                .font(.ax(.caption)).foregroundStyle(.secondary)
                                .rotationEffect(.degrees(-55))
                                .frame(width: 34, height: 42)
                        }
                        .id(index)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(dayLabel(point)): просмотрено \(point.count ?? 0) серий")
                    }
                }
                .padding(.horizontal)
            }
            .onAppear { reader.scrollTo(points.count - 1, anchor: .trailing) }
            .onChange(of: points) { _, _ in reader.scrollTo(points.count - 1, anchor: .trailing) }
        }
    }

    private func dayLabel(_ point: ProfileWatchDynamics) -> String {
        guard let timestamp = point.timestamp, timestamp > 0 else { return point.day.map(String.init) ?? "—" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(Locale(identifier: "ru_RU")))
    }
}

@MainActor
struct ProfileStatisticsHelpView: View {
    var body: some View {
        ProfileHelpSheet(title: "Как работает статистика", paragraphs: [
            "Здесь собираются данные о количестве релизов в ваших списках, времени просмотра и жанровых предпочтениях.",
            "Просмотренные серии, время и жанры рассчитываются ежедневно на основе релизов из списка «Просмотрено».",
            "Для расчёта жанровых предпочтений нужно не менее 10 релизов в списке «Просмотрено». Показываются до трёх основных жанров, а также по одному для аудитории и тематики.",
            "Например, после добавления «Самурай чамплу» (26 серий по 24 минуты) в «Просмотрено» на следующий день статистика увеличится на 26 серий и примерно 10 часов."
        ])
    }
}

@MainActor
struct ProfileHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let paragraphs: [String]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(paragraphs, id: \.self) { paragraph in
                        Text(paragraph).font(.ax(.body)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(24)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Понятно") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

@MainActor
struct ProfileVotesSection: View {
    let profile: Profile
    let viewer: ProfileViewerKey?

    var body: some View {
        VStack(spacing: 16) {
            if let votes = profile.votes, !votes.isEmpty {
                ForEach(votes) { release in
                    NavigationLink {
                        ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: viewer)
                    } label: { ProfileRatedReleaseRow(release: release).padding(.horizontal) }
                    .buttonStyle(.plain)
                }
            } else { ProfileEmptySection() }
            NavigationLink("Показать все") { ProfileVotesView(profileID: profile.id, viewer: viewer) }
                .font(.ax(.subheadline, .medium)).frame(maxWidth: .infinity).padding(.vertical, 10)
        }
    }
}

@MainActor
struct ProfileRatedReleaseRow: View {
    let release: Release
    var unrated = false

    var body: some View {
        HStack(spacing: 16) {
            ReleasePoster(url: release.posterURL, width: 52)
            VStack(alignment: .leading, spacing: 6) {
                Text(release.displayTitle).font(.ax(.subheadline)).foregroundStyle(.primary).lineLimit(2)
                HStack(spacing: 8) {
                    if unrated {
                        Text("Без оценки").font(.ax(.caption)).foregroundStyle(.secondary)
                    } else {
                        ProfileRatingStars(score: release.profileRating ?? 0)
                        if let timestamp = release.votedAt, timestamp > 0 {
                            Text("• \(ProfileDate.text(timestamp))").font(.ax(.caption)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

struct ProfileRatingStars: View {
    let score: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: "star.fill")
                    .foregroundStyle(star <= score ? Color.primary : Color.primary.opacity(0.13))
            }
        }
        .font(.ax(.caption))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Оценка \(score) из 5")
    }
}

@MainActor
struct ProfileCommentsSection: View {
    let profile: Profile
    let viewer: ProfileViewerKey?

    var body: some View {
        VStack(spacing: 16) {
            if let comments = profile.commentsPreview, !comments.isEmpty {
                ForEach(comments) { comment in
                    ProfileCommentLink(comment: comment, viewer: viewer).padding(.horizontal)
                }
                NavigationLink("Показать все") { ProfileCommentsView(profileID: profile.id, viewer: viewer) }
                    .font(.ax(.subheadline, .medium)).frame(maxWidth: .infinity).padding(.vertical, 10)
            } else { ProfileEmptySection() }
        }
    }
}

@MainActor
struct ProfileVideosSection: View {
    let profile: Profile
    let viewer: ProfileViewerKey?

    var body: some View {
        VStack(spacing: 16) {
            if let videos = profile.releaseVideosPreview, !videos.isEmpty {
                ForEach(videos) { video in
                    ProfileVideoEntry(video: video, viewer: viewer).padding(.horizontal)
                }
                NavigationLink("Показать все") { ProfileVideosView(profileID: profile.id, viewer: viewer) }
                    .font(.ax(.subheadline, .medium)).frame(maxWidth: .infinity).padding(.vertical, 10)
            } else { ProfileEmptySection() }
        }
    }
}

@MainActor
struct ProfileBadgesSection: View {
    let profile: Profile
    let viewer: ProfileViewerKey?

    var body: some View {
        VStack(spacing: 16) {
            if let badges = profile.badgesPreview, !badges.isEmpty {
                ProfileBadgePreviewGrid(badges: badges, totalCount: profile.badgeCount, profileID: profile.id, viewer: viewer)
            } else { ProfileEmptySection() }
        }
    }
}
