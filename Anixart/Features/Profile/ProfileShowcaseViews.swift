import SwiftUI
import AnixartKit

/// One profile theme behind the interchangeable section, including its chips
/// and non-badge content. Pinned badges stay in that section's badge grid.
@MainActor
struct ProfileThemedSection<Content: View>: View {
    let profile: Profile
    let content: Content

    init(profile: Profile, @ViewBuilder content: () -> Content) {
        self.profile = profile
        self.content = content()
    }

    var body: some View {
        content.background { ProfileShowcaseBackground(theme: profile.showcaseTheme) }
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
    @State private var account: ProfileAccountKey?
    @State private var model = ProfileBadgeOrderModel()

    init(profileID: Int, account: ProfileAccountKey?) {
        self.profileID = profileID
        _account = State(initialValue: account)
    }

    var body: some View {
        List {
            ProfileAccountNotice(account: account)
            if account != nil, env.session.accountKey == account {
            if model.resource.value != nil {
                if model.badges.count < 2 {
                    StatusMessageView(title: "Недостаточно значков", message: "Закрепите хотя бы 2 значка, чтобы изменить порядок", systemImage: "pin")
                } else {
                    Section {
                        ForEach(model.badges) { badge in
                            HStack(spacing: 16) { ProfileBadgeImage(badge: badge, size: 56); Text(badge.name ?? "Значок") }
                                .moveDisabled(!model.canReorder)
                        }
                        .onMove { from, to in model.move(fromOffsets: from, toOffset: to) }
                    } footer: { Text("Перетащите значки в нужном порядке и сохраните изменения.") }
                }
            } else { ProfileResourceState(resource: model.resource, title: "Не удалось загрузить витрину", retry: load) }
            if model.resource.value != nil, let error = model.resource.errorMessage {
                StatusMessageView(title: "Не удалось обновить витрину", message: error, retry: load)
            }
            ProfileSaveError(message: model.errorMessage)
            }
        }
        .environment(\.editMode, .constant(.active))
        .disabled(model.isSaving || account == nil || env.session.accountKey != account)
        .navigationTitle("Порядок значков")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { model.cancelChanges(); dismiss() }.disabled(model.isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { Task { await save() } }
                    .disabled(!model.canSave || env.session.accountKey != account)
            }
        }
        .task { if model.resource.value == nil { await load() } }
        .onChange(of: env.session.accountKey) { _, current in
            guard account != current else { return }
            model.reset()
        }
    }

    private func load() async {
        guard let account else { return }
        await model.load(profileID: profileID, account: account, session: env.session)
    }

    private func save() async {
        guard let account else { return }
        if await model.save(profileID: profileID, account: account, session: env.session) { dismiss() }
    }
}
