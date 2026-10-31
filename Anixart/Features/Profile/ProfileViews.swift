import SwiftUI
import UIKit
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
        .id(env.session.currentProfileID)
    }
}

/// Six interchangeable sections, followed by the same watch activity on every tab.
@MainActor
struct ProfileView: View {
    @Environment(AppEnvironment.self) private var env

    let profileID: Int
    var isOwnProfile = false
    let viewer: ProfileViewerKey?

    @State private var model = ProfileViewModel()
    @State private var isShowingSettings = false
    @State private var isShowingSearch = false
    @State private var searchViewer: ProfileViewerKey?
    @State private var isShowingLoginHistory = false
    @State private var loginHistoryViewer: ProfileViewerKey?
    @State private var notice: String?
    @State private var isChangingRelationship = false

    init(profileID: Int, isOwnProfile: Bool = false, viewer: ProfileViewerKey? = nil) {
        self.profileID = profileID
        self.isOwnProfile = isOwnProfile
        self.viewer = viewer
    }

    private var profile: Profile? { model.profile }
    private var isLoading: Bool { model.isLoading }
    private var errorMessage: String? { model.errorMessage }
    private var coverURL: URL? { model.coverURL }
    private var showcased: [Badge] { model.showcased }
    private var section: ProfileSection {
        get { model.section }
        nonmutating set { model.section = newValue }
    }

    private var ownsProfile: Bool {
        env.session.currentProfileID == profileID && (viewer == nil || viewer == env.session.viewerKey)
    }
    private var hasCurrentViewer: Bool { model.viewerKey == env.session.viewerKey }

    var body: some View {
        ScrollView {
            if let viewer, viewer != env.session.viewerKey {
                ProfileViewerNotice(viewer: viewer)
            } else if hasCurrentViewer, let profile {
                VStack(spacing: 0) {
                    identity(profile)
                    actions(profile)
                    if !showcased.isEmpty {
                        ProfileBadgeShowcase(profile: profile, badges: showcased, viewer: model.viewerKey)
                    }
                    sectionDivider
                    if profile.isCountsHidden != true {
                        friendsRow(profile)
                        sectionDivider
                    }
                    sectionChips
                    sectionContent(profile)
                    if profile.isStatsHidden != true {
                        ProfileActivitySection(profile: profile, viewer: model.viewerKey)
                    }
                }
                .padding(.bottom, Theme.Spacing.section)
            } else if isLoading || model.viewerKey != env.session.viewerKey && errorMessage == nil {
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
            if ownsProfile { searchHeader }
        }
        .toolbar(ownsProfile ? .hidden : .visible, for: .navigationBar)
        .navigationTitle(ownsProfile ? "" : (hasCurrentViewer ? profile?.displayLogin ?? "Профиль" : "Профиль"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load(force: true) }
        .task(id: ProfileReloadKey(profileID: profileID, profileRevision: env.session.profileRevision,
                                  sessionRevision: env.session.sessionRevision,
                                  viewerAccount: env.session.accountKey)) { await load(force: true) }
        .onChange(of: env.session.viewerKey) { _, current in
            model.invalidate(for: current)
            notice = nil
        }
        .navigationDestination(isPresented: $isShowingSearch) { UserSearchView(viewer: searchViewer) }
        .navigationDestination(isPresented: $isShowingLoginHistory) {
            ProfileLoginHistoryView(profileID: profileID, viewer: loginHistoryViewer)
        }
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
        .alert("Информация", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("Понятно", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    // MARK: - Header

    private var searchHeader: some View {
        GlassGroup(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    searchViewer = model.viewerKey
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
                .accessibilityLabel("Поиск пользователей")
                .disabled(!hasCurrentViewer)

                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.ax(.title3))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Настройки приложения")

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
            if let coverURL {
                CachedAsyncImage(url: coverURL, maxPixelSize: 1200) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(height: 150)
                .clipped()
                .padding(.bottom, -44)
            }
            Avatar(url: profile.avatarURL, size: 112, isOnline: profile.isOnline ?? false)
                .padding(.top, coverURL == nil ? 28 : 0)
                .padding(.bottom, 8)

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
                if ownsProfile {
                    NavigationLink {
                        ProfileEditorView(profileID: profileID, account: model.viewerAccount)
                    } label: {
                        Text("Редактировать")
                            .font(.ax(.headline))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .overlay(Capsule().stroke(.quaternary, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading || !hasCurrentViewer || model.viewerAccount == nil)
                } else {
                    Button {
                        let account = model.viewerAccount
                        Task { await toggleFriend(profile, for: account) }
                    } label: {
                        Text(friendButtonTitle(profile))
                            .font(.ax(.headline))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .overlay(Capsule().stroke(.quaternary, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isChangingRelationship || isLoading || !hasCurrentViewer)
                }

                Menu {
                    Button {
                        loginHistoryViewer = model.viewerKey
                        isShowingLoginHistory = true
                    } label: {
                        Label("История никнейма", systemImage: "clock.arrow.circlepath")
                    }
                    .disabled(!hasCurrentViewer)
                    ShareLink(item: AnixartEnvironment.webBaseURL.appendingPathComponent("profile/\(profileID)")) {
                        Label("Поделиться", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.url = AnixartEnvironment.webBaseURL.appendingPathComponent("profile/\(profileID)")
                        notice = "Ссылка на профиль скопирована"
                    } label: {
                        Label("Скопировать ссылку", systemImage: "link")
                    }
                    if !ownsProfile, env.session.isSignedIn {
                        Button(role: .destructive) {
                            let account = model.viewerAccount
                            Task { await toggleBlock(profile, for: account) }
                        } label: {
                            Label(profile.isBlocked == true ? "Разблокировать" : "Заблокировать", systemImage: "hand.raised")
                        }
                        .disabled(isChangingRelationship || isLoading || !hasCurrentViewer || model.viewerAccount == nil)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.ax(.headline))
                        .frame(width: 46, height: 46)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .foregroundStyle(.primary)
                .accessibilityLabel("Меню профиля")
            }

            HStack(spacing: 10) {
                ProfileSocialLinks(profile: profile)
                if ownsProfile {
                    NavigationLink {
                        ProfileSocialEditorView(profileID: profileID, account: model.viewerAccount)
                    } label: {
                        Image(systemName: "plus")
                            .font(.ax(.headline))
                            .frame(width: 58, height: 36)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Изменить социальные сети")
                    .disabled(isLoading || !hasCurrentViewer || model.viewerAccount == nil)
                }
            }
            .padding(.top, 4)
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
            FriendsView(profileID: profileID, viewer: model.viewerKey)
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
        HStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(ProfileSection.allCases) { candidate in
                            Button { section = candidate } label: {
                                Label(candidate.title, systemImage: candidate.systemImage)
                                    .font(.ax(.subheadline, section == candidate ? .medium : .regular))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color.primary.opacity(section == candidate ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
                                    .foregroundStyle(section == candidate ? .primary : .secondary)
                                }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(section == candidate ? .isSelected : [])
                            .id(candidate.id)
                        }
                    }
                    .padding(.leading)
                    .padding(.trailing, 8)
                }
                .onChange(of: section) { _, value in reader.scrollTo(value.id, anchor: .center) }
            }
            if ownsProfile {
                Menu {
                    NavigationLink { ProfileThemePickerView(account: model.viewerAccount) } label: {
                        Label("Тема витрины", systemImage: "paintpalette")
                    }
                    NavigationLink { ProfilePinnedSectionView(account: model.viewerAccount) } label: {
                        Label("Закрепить секцию", systemImage: "pin")
                    }
                    NavigationLink { ProfileBadgeOrderView(profileID: profileID, account: model.viewerAccount) } label: {
                        Label("Изменить порядок", systemImage: "arrow.up.arrow.down")
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.ax(.title3))
                        .frame(width: 48, height: 44)
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("Настройки секций профиля")
                .disabled(isLoading || !hasCurrentViewer || model.viewerAccount == nil)
            }
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func sectionContent(_ profile: Profile) -> some View {
        switch section {
        case .statistics:
            if profile.isStatsHidden ?? false {
                hiddenNotice
            } else {
                ProfileStatisticsSection(profile: profile, profileID: profileID, viewer: model.viewerKey)
            }
        case .votes:
            if profile.isStatsHidden == true { hiddenNotice }
            else { ProfileVotesSection(profile: profile, viewer: model.viewerKey) }
        case .collections:
            if profile.isCountsHidden == true { hiddenCountsNotice }
            else { ProfileCollectionsSection(collections: profile.collectionsPreview ?? [], profileID: profileID, viewer: model.viewerKey) }
        case .comments:
            if profile.isCountsHidden == true { hiddenCountsNotice }
            else { ProfileCommentsSection(profile: profile, viewer: model.viewerKey) }
        case .videos:
            if profile.isCountsHidden == true { hiddenCountsNotice }
            else { ProfileVideosSection(profile: profile, viewer: model.viewerKey) }
        case .badges:
            ProfileBadgesSection(profile: profile, viewer: model.viewerKey)
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

    private var hiddenCountsNotice: some View {
        ProfileEmptySection(message: "Пользователь предпочёл скрыть свои коллекции, комментарии, видео и друзей.")
    }

    // MARK: - Data

    private func load(force: Bool = false, expectedViewer: ProfileViewerKey? = nil) async {
        guard force || profile == nil else { return }
        await model.load(profileID: profileID, session: env.session, viewer: expectedViewer ?? viewer)
    }

    private func toggleFriend(_ profile: Profile, for account: ProfileAccountKey?) async {
        guard env.session.accountKey != nil else {
            env.session.promptSignIn()
            return
        }
        guard let account, env.session.accountKey == account, !isChangingRelationship,
              !isLoading, hasCurrentViewer else { return }
        let isFriend = profile.friendStatus == .friend
        isChangingRelationship = true
        defer { isChangingRelationship = false }
        do {
            try await env.session.sendConfirmedAccountRequest(
                isFriend || profile.friendStatus == .requestSent
                    ? ProfileEndpoints.removeFriend(profileID)
                    : ProfileEndpoints.sendFriendRequest(to: profileID), for: account
            )
            await load(force: true, expectedViewer: account.viewerKey)
            await env.session.refreshProfile(for: account)
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { notice = Paginator<Release>.message(for: error) }
        }
    }

    private func toggleBlock(_ profile: Profile, for account: ProfileAccountKey?) async {
        guard let account, env.session.accountKey == account, !isChangingRelationship,
              !isLoading, hasCurrentViewer else { return }
        isChangingRelationship = true
        defer { isChangingRelationship = false }
        do {
            try await env.session.sendConfirmedAccountRequest(profile.isBlocked == true
                ? ProfileEndpoints.unblock(profileID: profileID)
                : ProfileEndpoints.block(profileID: profileID), for: account)
            await load(force: true, expectedViewer: account.viewerKey)
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { notice = Paginator<Release>.message(for: error) }
        }
    }

    private func friendButtonTitle(_ profile: Profile) -> String {
        switch profile.friendStatus {
        case .friend: return "Удалить из друзей"
        case .requestSent: return "Отменить заявку"
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
    let viewer: ProfileViewerKey?
    @State private var isShowingHelp = false

    private var slices: [(status: ProfileListStatus, count: Int)] {
        ProfileListStatus.allCases.map { ($0, profile.listCount(for: $0)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            HStack(alignment: .center, spacing: Theme.Spacing.row) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(slices, id: \.status) { slice in
                        NavigationLink {
                            ProfileListView(profileID: profileID, status: slice.status, viewer: viewer)
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
                statLine("Жанры:", preferenceLine(profile.preferredGenres))
                statLine("Аудитория:", preferenceLine(profile.preferredAudiences))
                statLine("Тематика:", preferenceLine(profile.preferredThemes))
            }
            .padding(.horizontal)

            Button("Узнать подробнее") { isShowingHelp = true }
                .font(.ax(.subheadline, .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .sheet(isPresented: $isShowingHelp) { ProfileStatisticsHelpView() }
    }

    private func statLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).font(.ax(.subheadline, .medium))
            Text(value).font(.ax(.subheadline)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func preferenceLine(_ values: [ProfileGenre]?) -> String {
        let names = (values ?? []).compactMap { genre -> String? in
            guard let name = genre.name, !name.isEmpty else { return nil }
            return genre.percentage.map { "\(name) (\($0)%)" } ?? name
        }
        return names.isEmpty ? "Недостаточно данных" : names.joined(separator: ", ")
    }

    /// `watchedTime` is reported in seconds.
    private var watchedTimeText: String {
        let seconds = max(0, profile.watchedTime ?? 0)
        return "\(seconds / 86_400) дн. \((seconds % 86_400) / 3_600) ч."
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
        CachedAsyncImage(url: url, maxPixelSize: size) { image in
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
    var viewer: ProfileViewerKey?

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
                                ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: viewer)
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
    let viewer: ProfileViewerKey?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            if collections.isEmpty {
                ProfileEmptySection()
            } else {
                ForEach(collections) { collection in
                    NavigationLink {
                        CollectionDetailView(collection: collection, viewer: viewer)
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
                NavigationLink("Показать все") { ProfileCollectionsView(profileID: profileID, viewer: viewer) }
                    .font(.ax(.subheadline, .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
        }
    }
}

/// All five watch lists of a profile, one link each.
@MainActor
struct ProfileListsView: View {
    let profile: Profile
    var viewer: ProfileViewerKey?

    var body: some View {
        List {
            ForEach(ProfileListStatus.allCases) { status in
                NavigationLink {
                    ProfileListView(profileID: profile.id, status: status, viewer: viewer)
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

    @State private var viewer: ProfileViewerKey?
    @State private var paginator: Paginator<Release>?
    @State private var sort: BookmarkSort = .addedDescending

    init(profileID: Int, status: ProfileListStatus, viewer: ProfileViewerKey? = nil) {
        self.profileID = profileID
        self.status = status
        _viewer = State(initialValue: viewer)
    }

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Список пуст") { release in
                    NavigationLink {
                        ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: viewer)
                    } label: {
                        ReleaseRow(release: release)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(status.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Сортировка", selection: $sort) {
                    ForEach(BookmarkSort.allCases) { Text($0.title).tag($0) }
                }
            } label: { Image(systemName: "arrow.up.arrow.down") }
        } }
        .refreshable { await paginator?.reload() }
        .task(id: sort) {
            if viewer == nil { viewer = env.session.viewerKey }
            guard let viewer, viewer == env.session.viewerKey else { return }
            let session = env.session
            let id = profileID
            let status = self.status
            let sort = self.sort
            let list = Paginator<Release> { page in
                try await session.sendViewerRequest(BookmarkEndpoints.list(of: id, status: status, page: page, sort: sort), for: viewer)
            }
            paginator = list
            await list.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { paginator = nil }
        }
    }
}

/// Everything the profile has voted on.
@MainActor
struct ProfileVotesView: View {
    @Environment(AppEnvironment.self) private var env

    let profileID: Int
    @State private var viewer: ProfileViewerKey?
    @State private var paginator: Paginator<Release>?
    @State private var sort: ProfileVoteSort = .newest
    @State private var unrated = false
    @State private var rating: RatingRequest?
    @State private var isVoting = false
    @State private var voteError: String?

    init(profileID: Int, viewer: ProfileViewerKey? = nil) {
        self.profileID = profileID
        _viewer = State(initialValue: viewer)
    }

    private struct RatingRequest: Identifiable {
        let release: Release
        let account: ProfileAccountKey
        var id: Int { release.id }
    }

    private var account: ProfileAccountKey? { viewer?.account }
    private var ownsProfile: Bool { viewer == env.session.viewerKey && account?.profileID == profileID }

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: unrated ? "Все релизы оценены" : "Оценок пока нет") { release in
                    HStack {
                        NavigationLink {
                            ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: viewer)
                        } label: { ProfileRatedReleaseRow(release: release, unrated: unrated) }
                        if ownsProfile {
                            Button {
                                if let account { rating = RatingRequest(release: release, account: account) }
                            } label: {
                                Image(systemName: "star").font(.ax(.title3)).padding(10)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Оценить \(release.displayTitle)")
                            .disabled(isVoting)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Оценки релизов")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            if ownsProfile {
                Picker("Релизы", selection: $unrated) {
                    Text("Оценённые").tag(false)
                    Text("Неоценённые").tag(true)
                }
                .pickerStyle(.segmented).padding().background(.bar)
            }
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            if !unrated {
                Menu {
                    Picker("Сортировка", selection: $sort) {
                        ForEach(ProfileVoteSort.allCases) { Text($0.title).tag($0) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
            }
        } }
        .refreshable { await paginator?.reload() }
        .task(id: "\(unrated)-\(sort.rawValue)") {
            if viewer == nil { viewer = env.session.viewerKey }
            guard let viewer, viewer == env.session.viewerKey else { return }
            let session = env.session
            let account = viewer.account
            let id = profileID
            let sort = self.sort.rawValue
            let isUnrated = unrated && ownsProfile
            let list = Paginator<Release> { page in
                if isUnrated {
                    guard let account else { throw CancellationError() }
                    return try await session.sendAccountRequest(ProfileEndpoints.unratedReleases(page: page), for: account)
                }
                return try await session.sendViewerRequest(ProfileEndpoints.ratedReleases(profileID: id, page: page, sort: sort), for: viewer)
            }
            paginator = list
            await list.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            guard viewer != current else { return }
            paginator = nil
            rating = nil
            voteError = nil
        }
        .sheet(item: $rating) { request in
            RatingSheet(current: request.release.profileRating, distribution: request.release,
                         onVote: { score in Task { await vote(request, score: score) } },
                         onRemove: { Task { await vote(request, score: nil) } })
                .disabled(env.session.accountKey != request.account)
        }
        .alert("Не удалось сохранить оценку", isPresented: Binding(get: { voteError != nil }, set: { if !$0 { voteError = nil } })) {
            Button("Понятно", role: .cancel) { }
        } message: { Text(voteError ?? "") }
    }

    private func vote(_ request: RatingRequest, score: ReleaseVote?) async {
        guard ownsProfile, request.account == account, !isVoting else { return }
        let list = paginator
        isVoting = true
        voteError = nil
        defer { isVoting = false }
        do {
            if let score { try await env.session.sendConfirmedAccountRequest(ReleaseEndpoints.vote(releaseID: request.release.id, score: score), for: request.account) }
            else { try await env.session.sendConfirmedAccountRequest(ReleaseEndpoints.deleteVote(releaseID: request.release.id), for: request.account) }
            await list?.reload()
            await env.session.refreshProfile(for: request.account)
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { voteError = Paginator<Release>.message(for: error) }
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
