import SwiftUI
import AnixartKit

/// The Profile tab: the signed-in user's own profile, or a sign-in prompt.
@MainActor
struct ProfileTabView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        NavigationStack {
            Group {
                if let profileID = env.session.currentProfileID {
                    ProfileView(profileID: profileID, isOwnProfile: true)
                } else if env.session.state == .loading {
                    ProgressView()
                } else {
                    SignInPromptView(message: "Войдите, чтобы вести списки, оценивать и комментировать.")
                        .navigationTitle("Профиль")
                }
            }
        }
    }
}

/// Someone's profile, laid out as the Android `ProfileFragment` lays it out:
/// a centred identity block, the action buttons, a friends row, then the
/// statistics section with its legend and donut.
@MainActor
struct ProfileView: View {
    @Environment(AppEnvironment.self) private var env

    let profileID: Int
    var isOwnProfile = false

    @State private var profile: Profile?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isConfirmingSignOut = false
    @State private var isShowingSettings = false
    @State private var isShowingSearch = false
    @State private var section: ProfileSection = .statistics

    var body: some View {
        ScrollView {
            if let profile {
                VStack(spacing: 0) {
                    identity(profile)
                    actions(profile)
                    sectionDivider
                    friendsRow(profile)
                    sectionDivider
                    sectionChips
                    sectionContent(profile)
                }
                .padding(.bottom, Theme.Spacing.section)
            } else if isLoading {
                ProgressView().padding(.vertical, 80)
            } else if let errorMessage {
                StatusMessageView(
                    title: "Не удалось загрузить профиль",
                    message: errorMessage,
                    systemImage: "wifi.exclamationmark",
                    retry: { await load(force: true) }
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if isOwnProfile { searchHeader }
        }
        .toolbar(isOwnProfile ? .hidden : .visible, for: .navigationBar)
        .navigationTitle(isOwnProfile ? "" : (profile?.displayLogin ?? "Профиль"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load(force: true) }
        .task { await load() }
        .navigationDestination(isPresented: $isShowingSearch) { UserSearchView() }
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
        .confirmationDialog("Выйти из аккаунта?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) {
                Task { await env.session.signOut() }
            }
        }
    }

    // MARK: - Header

    private var searchHeader: some View {
        GlassGroup(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    isShowingSearch = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        Text("Поиск пользователей")
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .glassPill()
                }
                .buttonStyle(.plain)

                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.ax(.title3))
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    NotificationsView()
                } label: {
                    Image(systemName: "bell")
                        .font(.ax(.title3))
                        .foregroundStyle(.secondary)
                        .overlay(alignment: .topTrailing) {
                            if env.session.unreadNotifications > 0 {
                                Circle()
                                    .fill(Theme.accent)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 3, y: -2)
                            }
                        }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Identity

    private func identity(_ profile: Profile) -> some View {
        VStack(spacing: 8) {
            Avatar(url: profile.avatarURL, size: 112, isOnline: profile.isOnline ?? false)
                .padding(.top, 8)

            HStack(spacing: 6) {
                Text(profile.displayLogin)
                    .font(.ax(.title2, .bold))
                if profile.isSponsor ?? false {
                    Image(systemName: "crown.fill")
                        .font(.ax(.subheadline))
                        .foregroundStyle(Theme.sponsorGold)
                }
                if profile.isVerified ?? false {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.ax(.subheadline))
                        .foregroundStyle(Theme.accent)
                }
            }

            if let status = profile.status, !status.isEmpty {
                Text(status)
                    .font(.ax(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            HStack(spacing: 8) {
                if let score = profile.ratingScore {
                    Text("\(score)")
                        .font(.ax(.subheadline, .medium))
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Theme.listColor(.watching), lineWidth: 1)
                        )
                        .foregroundStyle(Theme.listColor(.watching))
                }
                if let joined = registered(profile) {
                    Text("• на проекте с \(joined)")
                        .font(.ax(.subheadline))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    @ViewBuilder
    private func actions(_ profile: Profile) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                if isOwnProfile {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Text("Редактировать")
                            .font(.ax(.headline))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .overlay(Capsule().stroke(.quaternary, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        Task { await toggleFriend(profile) }
                    } label: {
                        Text(friendButtonTitle(profile))
                            .font(.ax(.headline))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .overlay(Capsule().stroke(.quaternary, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                Menu {
                    if isOwnProfile {
                        Button {
                            isShowingSettings = true
                        } label: {
                            Label("Настройки", systemImage: "gearshape")
                        }
                        Button(role: .destructive) {
                            isConfirmingSignOut = true
                        } label: {
                            Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        Button {
                            // Reporting a profile is not part of the port yet.
                        } label: {
                            Label("Пожаловаться", systemImage: "flag")
                        }
                        .disabled(true)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.ax(.headline))
                        .frame(width: 46, height: 46)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .foregroundStyle(.primary)
            }

            // The "+" opens the badge showcase in the Android app; here it is the
            // shortcut to the lists, which is what there is to add to from a profile.
            NavigationLink {
                ProfileListsView(profile: profile)
            } label: {
                Image(systemName: "plus")
                    .font(.ax(.headline))
                    .frame(width: 70, height: 36)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(height: 8)
            .opacity(0.35)
    }

    // MARK: - Friends

    @ViewBuilder
    private func friendsRow(_ profile: Profile) -> some View {
        let friends = profile.friendsPreview ?? []
        NavigationLink {
            FriendsView(profileID: profileID)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Plural.friends(profile.friendCount ?? friends.count))
                        .font(.ax(.headline))
                        .foregroundStyle(.primary)
                    Text(
                        friends.isEmpty
                            ? "Друзей пока нет"
                            : friends.prefix(3).map(\.displayLogin).joined(separator: ", ")
                    )
                    .font(.ax(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 12)
                HStack(spacing: -10) {
                    ForEach(friends.prefix(3)) { friend in
                        Avatar(url: friend.avatarURL, size: 42, isOnline: false)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sections

    private var sectionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ProfileSection.allCases) { candidate in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { section = candidate }
                    } label: {
                        Label(candidate.title, systemImage: candidate.systemImage)
                            .font(.ax(.subheadline, section == candidate ? .medium : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background {
                                if section == candidate {
                                    Capsule().fill(Theme.accent.opacity(0.18))
                                } else {
                                    Capsule().stroke(.quaternary, lineWidth: 1)
                                }
                            }
                            .foregroundStyle(section == candidate ? Theme.accent : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func sectionContent(_ profile: Profile) -> some View {
        switch section {
        case .statistics:
            if profile.isStatsHidden ?? false {
                hiddenNotice
            } else {
                ProfileStatisticsSection(profile: profile, profileID: profileID)
            }
        case .votes:
            ProfilePreviewList(
                title: "Оценки релизов",
                releases: profile.votes ?? [],
                destination: { AnyView(ProfileVotesView(profileID: profileID)) },
                emptyMessage: "Оценённых релизов пока нет"
            )
        case .collections:
            ProfileCollectionsSection(
                collections: profile.collectionsPreview ?? [],
                profileID: profileID
            )
        }
    }

    private var hiddenNotice: some View {
        Text("Пользователь предпочёл скрыть свои данные о статистике и истории просмотра.")
            .font(.ax(.subheadline))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
    }

    // MARK: - Data

    private func load(force: Bool = false) async {
        guard force || profile == nil, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await env.client.send(ProfileEndpoints.profile(id: profileID))
            profile = response.profile
        } catch {
            errorMessage = Paginator<Release>.message(for: error)
        }
        isLoading = false
    }

    private func toggleFriend(_ profile: Profile) async {
        guard env.session.isSignedIn else {
            env.session.promptSignIn()
            return
        }
        let isFriend = profile.friendStatus == .friend
        _ = try? await env.client.send(
            isFriend
                ? ProfileEndpoints.removeFriend(profileID)
                : ProfileEndpoints.sendFriendRequest(to: profileID)
        )
        await load(force: true)
    }

    private func friendButtonTitle(_ profile: Profile) -> String {
        switch profile.friendStatus {
        case .friend: return "Удалить из друзей"
        case .requestSent: return "Заявка отправлена"
        case .requestReceived: return "Принять заявку"
        default: return "Добавить в друзья"
        }
    }

    private func registered(_ profile: Profile) -> String? {
        guard let registerDate = profile.registerDate, registerDate > 0 else { return nil }
        return Format.date(Date(timeIntervalSince1970: TimeInterval(registerDate)))
    }
}

// MARK: - Statistics

/// The legend, the donut and the watch totals, as the Android statistics tab shows them.
@MainActor
struct ProfileStatisticsSection: View {
    let profile: Profile
    let profileID: Int

    private var slices: [(status: ProfileListStatus, count: Int)] {
        ProfileListStatus.allCases.map { ($0, profile.listCount(for: $0)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            HStack(alignment: .center, spacing: Theme.Spacing.row) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(slices, id: \.status) { slice in
                        NavigationLink {
                            ProfileListView(profileID: profileID, status: slice.status)
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Theme.listColor(slice.status))
                                    .frame(width: 12, height: 12)
                                Text(slice.status.title)
                                    .font(.ax(.subheadline))
                                    .foregroundStyle(.primary)
                                Text("\(slice.count)")
                                    .font(.ax(.subheadline, .medium))
                                    .monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
                DonutChart(slices: slices.map { (color: Theme.listColor($0.status), value: $0.count) })
                    .frame(width: 140, height: 140)
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                statLine("Просмотрено серий:", Format.count(profile.watchedEpisodeCount))
                statLine("Время просмотра:", watchedTimeText)
                if let genres = preferenceLine(profile.preferredGenres) {
                    statLine("Жанры:", genres)
                }
                if let audiences = preferenceLine(profile.preferredAudiences) {
                    statLine("Аудитория:", audiences)
                }
                if let themes = preferenceLine(profile.preferredThemes) {
                    statLine("Тематика:", themes)
                }
            }
            .padding(.horizontal)

            if let history = profile.history, !history.isEmpty {
                ProfilePreviewList(
                    title: "Просмотрено недавно",
                    releases: history,
                    destination: nil,
                    emptyMessage: ""
                )
            }
        }
    }

    private func statLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).font(.ax(.subheadline, .medium))
            Text(value).font(.ax(.subheadline)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func preferenceLine(_ values: [ProfileGenre]?) -> String? {
        let names = (values ?? []).compactMap(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    /// `watchedTime` is reported in seconds.
    private var watchedTimeText: String {
        guard let seconds = profile.watchedTime, seconds > 0 else { return "—" }
        let hours = Double(seconds) / 3600
        return hours < 1
            ? "\(Int(Double(seconds) / 60)) мин."
            : String(format: "%.0f ч.", hours)
    }
}

/// The three chips under the friends row on a profile.
enum ProfileSection: String, CaseIterable, Identifiable {
    case statistics, votes, collections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .statistics: return "Статистика"
        case .votes: return "Оценки релизов"
        case .collections: return "Коллекции"
        }
    }

    var systemImage: String {
        switch self {
        case .statistics: return "chart.bar"
        case .votes: return "star"
        case .collections: return "square.on.square"
        }
    }
}

/// Donut of the five list counts, drawn in the Android chart's colours.
struct DonutChart: View {
    let slices: [(color: Color, value: Int)]

    private var total: Double { Double(slices.reduce(0) { $0 + $1.value }) }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let thickness = side * 0.28
            ZStack {
                if total <= 0 {
                    Circle()
                        .strokeBorder(.quaternary, lineWidth: thickness)
                } else {
                    ForEach(Array(angles.enumerated()), id: \.offset) { index, span in
                        Circle()
                            .trim(from: span.start, to: span.end)
                            .stroke(slices[index].color, lineWidth: thickness)
                            .rotationEffect(.degrees(-90))
                            .padding(thickness / 2)
                    }
                }
            }
            .frame(width: side, height: side)
        }
    }

    /// Fractions of the circle, with a hairline gap so neighbouring slices read apart.
    private var angles: [(start: CGFloat, end: CGFloat)] {
        guard total > 0 else { return [] }
        var cursor: CGFloat = 0
        return slices.map { slice in
            let fraction = CGFloat(Double(slice.value) / total)
            let span = (start: cursor, end: min(1, cursor + max(0, fraction - 0.004)))
            cursor += fraction
            return span
        }
    }
}

// MARK: - Shared pieces

/// Circular avatar with the Android online dot.
struct Avatar: View {
    let url: URL?
    var size: CGFloat = 44
    var isOnline: Bool = false

    var body: some View {
        CachedAsyncImage(url: url, maxPixelSize: 160) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Circle().fill(.quaternary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(alignment: .bottomTrailing) {
            if isOnline {
                Circle()
                    .fill(Theme.listColor(.watching))
                    .frame(width: size * 0.22, height: size * 0.22)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: size * 0.035))
            }
        }
    }
}

/// A horizontal strip of releases under a heading, used by several profile sections.
@MainActor
struct ProfilePreviewList: View {
    let title: String
    let releases: [Release]
    let destination: (() -> AnyView)?
    let emptyMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            SectionHeader(title: title) {
                if let destination {
                    NavigationLink("Показать все") { destination() }
                        .font(.ax(.subheadline))
                }
            }
            if releases.isEmpty {
                Text(emptyMessage)
                    .font(.ax(.subheadline))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Theme.Spacing.row) {
                        ForEach(releases) { release in
                            NavigationLink {
                                ReleaseDetailView(releaseID: release.id, preloaded: release)
                            } label: {
                                ReleaseCard(release: release)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

@MainActor
struct ProfileCollectionsSection: View {
    let collections: [ReleaseCollection]
    let profileID: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            if collections.isEmpty {
                Text("Коллекций пока нет")
                    .font(.ax(.subheadline))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                ForEach(collections) { collection in
                    NavigationLink {
                        CollectionDetailView(collection: collection)
                    } label: {
                        HStack(spacing: Theme.Spacing.row) {
                            CachedAsyncImage(url: collection.coverURL, maxPixelSize: 160) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle().fill(.quaternary)
                            }
                            .frame(width: 72, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(collection.displayTitle)
                                    .font(.ax(.headline))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Label(Format.count(collection.favoriteCount), systemImage: "heart")
                                    .labelStyle(.compact)
                                    .font(.ax(.caption))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// All five lists of a profile, one link each. Reached from the "+" button.
@MainActor
struct ProfileListsView: View {
    let profile: Profile

    var body: some View {
        List {
            ForEach(ProfileListStatus.allCases) { status in
                NavigationLink {
                    ProfileListView(profileID: profile.id, status: status)
                } label: {
                    HStack {
                        Circle()
                            .fill(Theme.listColor(status))
                            .frame(width: 10, height: 10)
                        Text(status.title)
                        Spacer()
                        Text(Format.count(profile.listCount(for: status)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Списки")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Someone's watch list, reachable from their profile.
@MainActor
struct ProfileListView: View {
    @Environment(AppEnvironment.self) private var env

    let profileID: Int
    let status: ProfileListStatus

    @State private var paginator: Paginator<Release>?

    var body: some View {
        List {
            if let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Список пуст") { release in
                    NavigationLink {
                        ReleaseDetailView(releaseID: release.id, preloaded: release)
                    } label: {
                        ReleaseRow(release: release)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(status.title)
        .task {
            if paginator == nil {
                let client = env.client
                let id = profileID
                let status = self.status
                paginator = Paginator { page in
                    try await client.send(BookmarkEndpoints.list(of: id, status: status, page: page))
                }
            }
            await paginator?.loadFirstPageIfNeeded()
        }
    }
}

/// Everything the profile has voted on.
@MainActor
struct ProfileVotesView: View {
    @Environment(AppEnvironment.self) private var env

    let profileID: Int
    @State private var paginator: Paginator<Release>?

    var body: some View {
        List {
            if let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Оценок пока нет") { release in
                    NavigationLink {
                        ReleaseDetailView(releaseID: release.id, preloaded: release)
                    } label: {
                        ReleaseRow(release: release)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Оценки релизов")
        .task {
            if paginator == nil {
                let client = env.client
                let id = profileID
                paginator = Paginator { page in
                    try await client.send(ProfileEndpoints.ratedReleases(profileID: id, page: page))
                }
            }
            await paginator?.loadFirstPageIfNeeded()
        }
    }
}

@MainActor
struct FriendsView: View {
    @Environment(AppEnvironment.self) private var env
    let profileID: Int
    @State private var paginator: Paginator<Profile>?

    var body: some View {
        List {
            if let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Друзей пока нет") { friend in
                    NavigationLink {
                        ProfileView(profileID: friend.id)
                    } label: {
                        HStack(spacing: Theme.Spacing.row) {
                            Avatar(url: friend.avatarURL, size: 40, isOnline: friend.isOnline ?? false)
                            Text(friend.displayLogin)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Друзья")
        .task {
            if paginator == nil {
                let client = env.client
                let id = profileID
                paginator = Paginator { page in
                    try await client.send(ProfileEndpoints.friends(of: id, page: page))
                }
            }
            await paginator?.loadFirstPageIfNeeded()
        }
    }
}

/// Russian plural forms, which Android gets from `plurals.xml`.
enum Plural {
    static func friends(_ count: Int) -> String {
        forms(count, one: "друг", few: "друга", many: "друзей")
    }

    static func votes(_ count: Int) -> String {
        forms(count, one: "голос", few: "голоса", many: "голосов")
    }

    static func replies(_ count: Int) -> String {
        forms(count, one: "ответ", few: "ответа", many: "ответов")
    }

    static func episodes(_ count: Int) -> String {
        forms(count, one: "эпизод", few: "эпизода", many: "эпизодов")
    }

    private static func forms(_ count: Int, one: String, few: String, many: String) -> String {
        let value = "\(Format.count(count)) "
        let mod100 = count % 100
        if (11...14).contains(mod100) { return value + many }
        switch count % 10 {
        case 1: return value + one
        case 2...4: return value + few
        default: return value + many
        }
    }
}
