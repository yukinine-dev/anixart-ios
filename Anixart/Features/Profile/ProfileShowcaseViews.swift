import SwiftUI
import AnixartKit

@MainActor
struct ProfileBadgeShowcase: View {
    let profile: Profile
    let badges: [Badge]
    let viewer: ProfileViewerKey?
    var body: some View {
        ProfileBadgeStrip(badges: Array(badges.prefix(ProfileEditorRules.showcaseLimit)), profileID: profile.id, viewer: viewer)
            .padding(.vertical, 22)
    }
}

@MainActor
struct ProfileThemePickerView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var resource = ProfileResource<ProfilePreferenceResponse>()
    @State private var account: ProfileAccountKey?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(account: ProfileAccountKey?) { _account = State(initialValue: account) }

    var body: some View {
        List {
            ProfileAccountNotice(account: account)
            if env.session.accountKey == account, account != nil, let preferences = resource.value {
                Section {
                    ForEach(preferences.availableThemes ?? []) { theme in
                        Button { Task { await select(theme.id) } } label: {
                            HStack {
                                Text(theme.name ?? "Тема \(theme.id)").foregroundStyle(.primary)
                                Spacer()
                                if preferences.selectedThemeId == theme.id { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                            .padding(.vertical, 10)
                        }
                        .disabled(isSaving || env.session.accountKey != account)
                    }
                } footer: {
                    Text("Доступные темы зависят от предпочитаемых жанров, аудитории и тематик. Для формирования статистики необходимо не менее 10 релизов в списке «Просмотрено». Данные обновляются раз в сутки.")
                }
            } else if env.session.accountKey == account, account != nil {
                ProfileResourceState(resource: resource, title: "Не удалось загрузить темы", retry: load)
            }
            ProfileSaveError(message: errorMessage ?? resource.errorMessage)
        }
        .navigationTitle("Тема витрины")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: env.session.accountKey) { _, current in
            if account != current { resource.reset(); errorMessage = nil }
        }
    }

    private func load() async {
        guard let account else { return }
        await resource.load { try await env.session.sendAccountRequest(ProfilePreferenceEndpoints.my(), for: account) }
    }

    private func select(_ id: Int) async {
        guard !isSaving, let account, resource.value?.availableThemes?.contains(where: { $0.id == id }) == true else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await env.session.sendConfirmedAccountRequest(ProfilePreferenceEndpoints.selectTheme(id: id), for: account)
            await load()
            await env.session.refreshProfile(for: account)
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
        }
    }
}

@MainActor
struct ProfilePinnedSectionView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var resource = ProfileResource<ProfilePreferenceResponse>()
    @State private var account: ProfileAccountKey?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(account: ProfileAccountKey?) { _account = State(initialValue: account) }

    var body: some View {
        List {
            ProfileAccountNotice(account: account)
            if env.session.accountKey == account, account != nil, let preferences = resource.value {
                Section {
                    ForEach(ProfileSection.allCases) { section in
                        Button { Task { await select(section) } } label: {
                            HStack {
                                Label(section.title, systemImage: section.systemImage).foregroundStyle(.primary)
                                Spacer()
                                if (preferences.pinnedSectionId ?? 0) == section.id { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                            .padding(.vertical, 10)
                        }
                        .disabled(isSaving || env.session.accountKey != account)
                    }
                } footer: { Text("Эта секция будет открываться первой при посещении вашего профиля.") }
            } else if env.session.accountKey == account, account != nil {
                ProfileResourceState(resource: resource, title: "Не удалось загрузить секции", retry: load)
            }
            ProfileSaveError(message: errorMessage ?? resource.errorMessage)
        }
        .navigationTitle("Закрепить секцию")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await load() }
        .onChange(of: env.session.accountKey) { _, current in
            if account != current { resource.reset(); errorMessage = nil }
        }
    }

    private func load() async {
        guard let account else { return }
        await resource.load { try await env.session.sendAccountRequest(ProfilePreferenceEndpoints.my(), for: account) }
    }

    private func select(_ section: ProfileSection) async {
        guard !isSaving, let account else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await env.session.sendConfirmedAccountRequest(ProfilePreferenceEndpoints.pinSection(section), for: account)
            await load()
            await env.session.refreshProfile(for: account)
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
        }
    }
}

@MainActor
struct ProfileBadgeOrderView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let profileID: Int
    @State private var resource = ProfileResource<ProfileBadgeSectionsResponse>()
    @State private var account: ProfileAccountKey?
    @State private var badges: [Badge] = []
    @State private var originalIDs: [Int] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(profileID: Int, account: ProfileAccountKey?) {
        self.profileID = profileID
        _account = State(initialValue: account)
    }

    var body: some View {
        List {
            ProfileAccountNotice(account: account)
            if account != nil, env.session.accountKey == account {
            if resource.value != nil {
                if badges.count < 2 {
                    StatusMessageView(title: "Недостаточно значков", message: "Закрепите хотя бы 2 значка, чтобы изменить порядок", systemImage: "pin")
                } else {
                    Section {
                        ForEach(badges) { badge in
                            HStack(spacing: 16) { ProfileBadgeImage(badge: badge, size: 56); Text(badge.name ?? "Значок") }
                        }
                        .onMove { from, to in badges.move(fromOffsets: from, toOffset: to) }
                    } footer: { Text("Перетащите значки в нужном порядке и сохраните изменения.") }
                }
            } else { ProfileResourceState(resource: resource, title: "Не удалось загрузить витрину", retry: load) }
            ProfileSaveError(message: errorMessage ?? resource.errorMessage)
            }
        }
        .environment(\.editMode, .constant(.active))
        .disabled(isSaving || account == nil || env.session.accountKey != account)
        .navigationTitle("Порядок значков")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .confirmationAction) {
            Button("Сохранить") { Task { await save() } }
                .disabled(isSaving || badges.count < 2 || badges.map(\.id) == originalIDs || env.session.accountKey != account)
        } }
        .task { await load() }
        .onChange(of: env.session.accountKey) { _, current in
            guard account != current else { return }
            resource.reset()
            badges = []
            originalIDs = []
            errorMessage = nil
        }
    }

    private func load() async {
        guard let account, account.profileID == profileID else { return }
        if let response = await resource.load({ try await env.session.sendAccountRequest(ProfileBadgeEndpoints.sections(profileID: profileID), for: account) }) {
            badges = response.showcased ?? []
            originalIDs = badges.map(\.id)
        }
    }

    private func save() async {
        guard !isSaving, let account, account.profileID == profileID,
              (2...ProfileEditorRules.showcaseLimit).contains(badges.count),
              Set(badges.map(\.id)) == Set(originalIDs) else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await env.session.sendConfirmedAccountRequest(ProfileBadgeEndpoints.reorder(ids: badges.map(\.id)), for: account)
            await env.session.refreshProfile(for: account)
            if env.session.accountKey == account, !Task.isCancelled { dismiss() }
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
        }
    }
}
