import SwiftUI
import AnixartKit

@MainActor
struct FriendsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case friends, incoming, outgoing
        var id: String { rawValue }
        var title: String {
            switch self {
            case .friends: return "Друзья"
            case .incoming: return "Входящие"
            case .outgoing: return "Исходящие"
            }
        }
        var emptyTitle: String { self == .friends ? "Друзей пока нет" : "Заявок нет" }
    }

    @Environment(AppEnvironment.self) private var env
    let profileID: Int
    @State private var viewer: ProfileViewerKey?
    @State private var tab: Tab = .friends
    @State private var paginator: Paginator<Profile>?
    @State private var savingIDs = Set<Int>()
    @State private var pendingRemoval: Profile?
    @State private var errorMessage: String?

    init(profileID: Int, viewer: ProfileViewerKey? = nil) {
        self.profileID = profileID
        _viewer = State(initialValue: viewer)
    }

    private var account: ProfileAccountKey? { viewer?.account }
    private var ownsProfile: Bool { viewer == env.session.viewerKey && account?.profileID == profileID }

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: tab.emptyTitle) { profile in
                    HStack(spacing: 8) {
                        NavigationLink { ProfileView(profileID: profile.id, viewer: viewer) } label: { ProfileFriendRow(profile: profile) }
                        if ownsProfile { actions(profile).disabled(savingIDs.contains(profile.id)) }
                    }
                }
            }
            ProfileSaveError(message: errorMessage)
        }
        .listStyle(.plain)
        .navigationTitle("Друзья")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            if ownsProfile {
                Picker("Раздел друзей", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).padding().background(.bar)
            }
        }
        .refreshable { await paginator?.reload() }
        .task(id: tab) {
            if viewer == nil { viewer = env.session.viewerKey }
            guard let viewer, viewer == env.session.viewerKey else { return }
            let session = env.session
            let account = viewer.account
            let id = profileID
            let tab = self.tab
            let list = Paginator<Profile> { page in
                if tab == .friends {
                    return try await session.sendViewerRequest(ProfileEndpoints.friends(of: id, page: page), for: viewer)
                }
                guard let account, account.profileID == id else { throw CancellationError() }
                return try await session.sendAccountRequest(tab == .incoming
                    ? ProfileEndpoints.incomingFriendRequests(page: page)
                    : ProfileEndpoints.outgoingFriendRequests(page: page), for: account)
            }
            paginator = list
            await list.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            guard viewer != current else { return }
            paginator = nil
            pendingRemoval = nil
            errorMessage = nil
        }
        .confirmationDialog("Удалить из друзей?", isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }
        ), titleVisibility: .visible) {
            if let profile = pendingRemoval {
                Button("Удалить из друзей", role: .destructive) { Task { await change(profile, accept: false) } }
            }
        } message: { Text(pendingRemoval?.displayLogin ?? "") }
    }

    @ViewBuilder
    private func actions(_ profile: Profile) -> some View {
        switch tab {
        case .friends:
            Menu {
                Button("Удалить из друзей", role: .destructive) { pendingRemoval = profile }
            } label: { Image(systemName: "ellipsis").padding(10) }
            .accessibilityLabel("Действия с другом \(profile.displayLogin)")
        case .incoming:
            Button { Task { await change(profile, accept: true) } } label: { Image(systemName: "checkmark").padding(10) }
                .buttonStyle(.borderless).accessibilityLabel("Принять заявку \(profile.displayLogin)")
            Button { Task { await change(profile, accept: false) } } label: { Image(systemName: "xmark").padding(10) }
                .buttonStyle(.borderless).accessibilityLabel("Отклонить заявку \(profile.displayLogin)")
        case .outgoing:
            Button { Task { await change(profile, accept: false) } } label: { Image(systemName: "xmark").padding(10) }
                .buttonStyle(.borderless).accessibilityLabel("Отменить заявку \(profile.displayLogin)")
        }
    }

    private func change(_ profile: Profile, accept: Bool) async {
        guard ownsProfile, let account, !savingIDs.contains(profile.id) else { return }
        savingIDs.insert(profile.id)
        errorMessage = nil
        let list = paginator
        defer { savingIDs.remove(profile.id) }
        do {
            try await env.session.sendConfirmedAccountRequest(accept
                ? ProfileEndpoints.sendFriendRequest(to: profile.id)
                : ProfileEndpoints.removeFriend(profile.id), for: account)
            await list?.removeAndReload(id: profile.id)
            await env.session.refreshProfile(for: account)
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
        }
    }
}
