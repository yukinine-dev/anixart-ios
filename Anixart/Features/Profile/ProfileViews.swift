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

@MainActor
struct ProfileView: View {
    @Environment(AppEnvironment.self) private var env

    let profileID: Int
    var isOwnProfile = false

    @State private var profile: Profile?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isConfirmingSignOut = false

    var body: some View {
        List {
            if let profile {
                header(profile)
                statistics(profile)
                if isOwnProfile {
                    navigation(profile)
                    account
                }
            } else if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let errorMessage {
                StatusMessageView(
                    title: "Не удалось загрузить профиль",
                    message: errorMessage,
                    systemImage: "wifi.exclamationmark",
                    retry: { await load() }
                )
            }
        }
        .navigationTitle(profile?.displayLogin ?? "Профиль")
        .refreshable { await load(force: true) }
        .task { await load() }
        .confirmationDialog("Выйти из аккаунта?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) {
                Task { await env.session.signOut() }
            }
        }
    }

    // MARK: - Sections

    private func header(_ profile: Profile) -> some View {
        HStack(spacing: Theme.Spacing.row) {
            AsyncImage(url: profile.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(.quaternary)
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(profile.displayLogin).font(.headline)
                    if profile.isVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                }
                if let status = profile.status, !status.isEmpty {
                    Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if profile.isOnline == true {
                    Label("в сети", systemImage: "circle.fill")
                        .labelStyle(.compact)
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else if let last = Format.relativeDate(lastSeen(profile)) {
                    Text("был \(last)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statistics(_ profile: Profile) -> some View {
        Section("Списки") {
            ForEach(ProfileListStatus.allCases) { status in
                NavigationLink {
                    ProfileListView(profileID: profileID, status: status)
                } label: {
                    HStack {
                        Label(status.title, systemImage: status.systemImage)
                        Spacer()
                        Text(Format.count(profile.listCount(for: status)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }

        Section("Статистика") {
            statRow("Просмотрено серий", Format.count(profile.watchedEpisodeCount))
            statRow("Время просмотра", watchedTimeText(profile))
            statRow("Комментариев", Format.count(profile.commentCount))
            statRow("Коллекций", Format.count(profile.collectionCount))
            statRow("Друзей", Format.count(profile.friendCount))
            if !(profile.preferredGenres?.isEmpty ?? true) {
                let genres = (profile.preferredGenres ?? [])
                    .compactMap(\.name)
                    .joined(separator: ", ")
                statRow("Любимые жанры", genres)
            }
        }
    }

    @ViewBuilder
    private func navigation(_ profile: Profile) -> some View {
        Section {
            NavigationLink {
                NotificationsView()
            } label: {
                HStack {
                    Label("Уведомления", systemImage: "bell")
                    Spacer()
                    if env.session.unreadNotifications > 0 {
                        Text("\(env.session.unreadNotifications)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.accent, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            }
            NavigationLink {
                FriendsView(profileID: profileID)
            } label: {
                Label("Друзья", systemImage: "person.2")
            }
        }
    }

    private var account: some View {
        Section {
            Button("Выйти", role: .destructive) { isConfirmingSignOut = true }
        } footer: {
            Text("Данные берутся из официального API Anixart. Это неофициальный клиент.")
        }
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
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

    private func lastSeen(_ profile: Profile) -> Date? {
        guard let timestamp = profile.lastActivityTime, timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    /// `watchedTime` is reported in seconds.
    private func watchedTimeText(_ profile: Profile) -> String {
        guard let seconds = profile.watchedTime, seconds > 0 else { return "—" }
        let hours = Double(seconds) / 3600
        return hours < 1
            ? "\(Int(Double(seconds) / 60)) мин."
            : String(format: "%.0f ч.", hours)
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
                            AsyncImage(url: friend.avatarURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Circle().fill(.quaternary)
                            }
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
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
