import SwiftUI
import AnixartKit

@MainActor
struct FriendsView: View {
    @Environment(AppEnvironment.self) private var env
    let profileID: Int
    @State private var viewer: ProfileViewerKey?
    @State private var model: ProfileFriendsModel?
    @State private var pendingRemoval: Profile?

    init(profileID: Int, viewer: ProfileViewerKey? = nil) {
        self.profileID = profileID
        _viewer = State(initialValue: viewer)
    }

    private var ownsProfile: Bool { model?.ownsList == true }

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if let model, model.hasCurrentViewer {
                if ownsProfile {
                    group(.incoming, title: "Входящие заявки")
                    group(.outgoing, title: "Исходящие заявки")
                }
                group(.friends, title: ownsProfile ? "Мои друзья" : "Список друзей")
                if ownsProfile {
                    if let response = model.recommendations.value, !response.items.isEmpty {
                        Section("Возможные друзья") {
                            ForEach(response.items) { profile in
                                HStack {
                                    NavigationLink { ProfileView(profileID: profile.id, viewer: viewer) } label: { ProfileFriendRow(profile: profile) }
                                    Button {
                                        Task { await model.change(profile, action: .send) }
                                    } label: { Image(systemName: "person.badge.plus").padding(10) }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Добавить в друзья \(profile.displayLogin)")
                                    .disabled(model.savingIDs.contains(profile.id) || profile.friendRelationship(viewerID: profileID) != .none)
                                }
                            }
                        }
                    } else if model.recommendations.errorMessage != nil {
                        ProfileResourceState(resource: model.recommendations, title: "Не удалось загрузить возможных друзей",
                                             retry: { await model.load(refresh: true) })
                    }
                }
                ProfileSaveError(message: model.errorMessage)
            }
        }
        .listStyle(.plain)
        .navigationTitle(ownsProfile ? "Мои друзья" : "Список друзей")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await model?.load(refresh: true) }
        .task {
            if viewer == nil { viewer = env.session.viewerKey }
            guard let viewer, viewer == env.session.viewerKey else { return }
            if model == nil { model = ProfileFriendsModel(ownerID: profileID, viewer: viewer, session: env.session) }
            await model?.load()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            guard viewer != current else { return }
            model?.invalidate(for: current)
            pendingRemoval = nil
        }
        .confirmationDialog("Удалить из друзей?", isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }
        ), titleVisibility: .visible) {
            if let profile = pendingRemoval {
                Button("Удалить из друзей", role: .destructive) { Task { await model?.change(profile, action: .remove) } }
            }
        } message: { Text(pendingRemoval?.displayLogin ?? "") }
    }

    @ViewBuilder
    private func actions(_ profile: Profile, group: ProfileFriendsModel.Group) -> some View {
        switch group {
        case .friends:
            Menu {
                Button("Удалить из друзей", role: .destructive) { pendingRemoval = profile }
            } label: { Image(systemName: "ellipsis").padding(10) }
            .accessibilityLabel("Действия с другом \(profile.displayLogin)")
        case .incoming:
            Button { Task { await model?.change(profile, action: .accept) } } label: { Image(systemName: "checkmark").padding(10) }
                .buttonStyle(.borderless).accessibilityLabel("Принять заявку \(profile.displayLogin)")
            Button { Task { await model?.change(profile, action: .hide) } } label: { Image(systemName: "xmark").padding(10) }
                .buttonStyle(.borderless).accessibilityLabel("Отклонить заявку \(profile.displayLogin)")
        case .outgoing:
            Button { Task { await model?.change(profile, action: .cancel) } } label: { Image(systemName: "xmark").padding(10) }
                .buttonStyle(.borderless).accessibilityLabel("Отменить заявку \(profile.displayLogin)")
        }
    }

    @ViewBuilder
    private func group(_ group: ProfileFriendsModel.Group, title: String) -> some View {
        if let model, let list = model.lists[group], group == .friends || !list.isEmpty {
            Section {
                PaginatedContent(paginator: list, emptyTitle: "Друзей пока нет") { profile in
                    HStack(spacing: 8) {
                        NavigationLink { ProfileView(profileID: profile.id, viewer: viewer) } label: { ProfileFriendRow(profile: profile) }
                        if ownsProfile { actions(profile, group: group).disabled(model.savingIDs.contains(profile.id)) }
                    }
                }
            } header: {
                Text(title + (list.totalCount.map { " · \(Format.count($0))" } ?? ""))
            }
        }
    }
}
