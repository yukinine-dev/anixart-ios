import SwiftUI
import AnixartKit

@MainActor
struct ProfileHiddenChannelsView: View {
    @Environment(AppEnvironment.self) private var env
    let account: ProfileAccountKey?
    @State private var paginator: Paginator<Channel>?
    @State private var pending: Channel?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            ProfileAccountNotice(account: account)
            if env.session.accountKey == account, let account, let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Скрытых каналов нет",
                                 emptyMessage: "Здесь появятся каналы, которые вы скрыли из ленты.") { channel in
                    HStack(spacing: 14) {
                        NavigationLink {
                            ProfileChannelView(channelID: channel.id, preloaded: channel, viewer: account.viewerKey)
                        } label: { ProfileChannelRow(channel: channel) }
                        Button { pending = channel } label: { Image(systemName: "eye").padding(8) }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Показывать канал \(channel.title ?? "")")
                            .disabled(isSaving || env.session.accountKey != account)
                    }
                }
            }
            ProfileSaveError(message: errorMessage)
        }
        .listStyle(.plain)
        .navigationTitle("Скрытые каналы")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await paginator?.reload() }
        .task {
            guard let account else { return }
            if paginator == nil {
                let session = env.session
                paginator = Paginator { page in
                    try await session.sendAccountRequest(ChannelEndpoints.hidden(page: page), for: account)
                }
            }
            await paginator?.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.accountKey) { _, current in
            if account != current { paginator = nil; pending = nil; errorMessage = nil }
        }
        .confirmationDialog("Показывать канал в ленте?", isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }
        ), titleVisibility: .visible) {
            if let channel = pending {
                Button("Показывать") { Task { await unhide(channel) } }
            }
        } message: { Text(pending?.title ?? "Канал снова будет виден в ленте.") }
    }

    private func unhide(_ channel: Channel) async {
        guard !isSaving, let account else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await env.session.sendConfirmedAccountRequest(ChannelEndpoints.unhide(channelID: channel.id), for: account)
            await paginator?.removeAndReload(id: channel.id)
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
        }
    }
}

@MainActor
struct ProfileBlockListView: View {
    @Environment(AppEnvironment.self) private var env
    let account: ProfileAccountKey?
    @State private var paginator: Paginator<Profile>?
    @State private var pending: Profile?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            ProfileAccountNotice(account: account)
            if env.session.accountKey == account, let account, let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Блоклист пуст",
                                 emptyMessage: "Здесь появятся заблокированные вами пользователи.") { profile in
                    HStack(spacing: 14) {
                        NavigationLink { ProfileView(profileID: profile.id, viewer: account.viewerKey) } label: { ProfileFriendRow(profile: profile) }
                        Button { pending = profile } label: { Image(systemName: "person.crop.circle.badge.checkmark").padding(8) }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Разблокировать \(profile.displayLogin)")
                            .disabled(isSaving || env.session.accountKey != account)
                    }
                }
            }
            ProfileSaveError(message: errorMessage)
        }
        .listStyle(.plain)
        .navigationTitle("Блоклист")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await paginator?.reload() }
        .task {
            guard let account else { return }
            if paginator == nil {
                let session = env.session
                paginator = Paginator { page in
                    try await session.sendAccountRequest(ProfileEndpoints.blockList(page: page), for: account)
                }
            }
            await paginator?.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.accountKey) { _, current in
            if account != current { paginator = nil; pending = nil; errorMessage = nil }
        }
        .confirmationDialog("Разблокировать пользователя?", isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }
        ), titleVisibility: .visible) {
            if let profile = pending {
                Button("Разблокировать") { Task { await unblock(profile) } }
            }
        } message: { Text("\(pending?.displayLogin ?? "Пользователь") снова сможет просматривать вашу страницу с учётом настроек приватности.") }
    }

    private func unblock(_ profile: Profile) async {
        guard !isSaving, let account else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await env.session.sendConfirmedAccountRequest(ProfileEndpoints.unblock(profileID: profile.id), for: account)
            await paginator?.removeAndReload(id: profile.id)
            await env.session.refreshProfile(for: account)
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
        }
    }
}

struct ProfileFriendRow: View {
    let profile: Profile
    var body: some View {
        HStack(spacing: 14) {
            Avatar(url: profile.avatarURL, size: 44, isOnline: profile.isOnline == true)
            Text(profile.displayLogin).font(.ax(.body)).foregroundStyle(.primary)
            if profile.isVerified == true { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.accent) }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}
