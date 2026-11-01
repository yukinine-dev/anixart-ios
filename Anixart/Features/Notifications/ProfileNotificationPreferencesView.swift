import SwiftUI
import AnixartKit

@MainActor
struct ProfileNotificationPreferencesView: View {
    @Environment(AppEnvironment.self) private var env
    let account: ProfileAccountKey?
    @State private var resource = ProfileResource<NotificationPreferencesResponse>()
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            ProfileAccountNotice(account: account)
            if let account, env.session.accountKey == account {
                if let preferences = resource.value {
                    Section("Новые серии") {
                        flag(.episode, preferences)
                        flag(.firstEpisode, preferences)
                        flag(.selectedReleases, preferences)
                        NavigationLink("Из выбранных списков") { ProfileNotificationListsSelector(account: account) }
                        NavigationLink("Озвучки") { ProfileNotificationVoicesSelector(account: account) }
                        NavigationLink("Выбранные релизы") { ProfileNotificationReleasesView(account: account) }
                    }
                    Section("Другие события") {
                        ForEach([NotificationPreferenceFlag.relatedRelease, .article, .comment, .myCollectionComment, .myArticleComment, .reportProcess]) {
                            flag($0, preferences)
                        }
                    }
                    Section {
                        Text("Настройки сохраняются в Anixart. Доставка push-уведомлений на iOS пока не реализована.")
                            .font(.ax(.caption)).foregroundStyle(.secondary)
                    }
                    ProfileSaveError(message: errorMessage ?? resource.errorMessage)
                } else { ProfileResourceState(resource: resource, title: "Не удалось загрузить настройки уведомлений", retry: load) }
            }
        }
        .navigationTitle("Настройки уведомлений").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await load() }
        .refreshable { if !isSaving { await load() } }
        .onChange(of: env.session.accountKey) { _, current in
            if account != current { resource.reset(); errorMessage = nil }
        }
    }

    @ViewBuilder
    private func flag(_ flag: NotificationPreferenceFlag, _ preferences: NotificationPreferencesResponse) -> some View {
        if let value = preferences.value(for: flag) {
            Toggle(flag.title, isOn: Binding(get: { resource.value?.value(for: flag) ?? value }, set: { desired in
                Task { await set(flag, desired: desired) }
            }))
            .disabled(isSaving || resource.isLoading || resource.errorMessage != nil)
        } else { LabeledContent(flag.title, value: "Неизвестно") }
    }

    private func load() async {
        guard let account else { return }
        await resource.load { try await env.session.sendAccountRequest(NotificationPreferenceEndpoints.my(), for: account) }
    }

    private func set(_ flag: NotificationPreferenceFlag, desired: Bool) async {
        guard !isSaving, let account, env.session.accountKey == account,
              let current = resource.value?.value(for: flag), current != desired else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await env.session.sendConfirmedAccountRequest(NotificationPreferenceEndpoints.toggle(flag), for: account)
            await load()
            await env.session.refreshProfile(for: account)
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
        }
    }
}

@MainActor
struct ProfileNotificationListsSelector: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let account: ProfileAccountKey
    @State private var resource = ProfileResource<NotificationPreferencesResponse>()
    @State private var selected = Set<Int>()
    @State private var isSaving = false
    @State private var isPrepared = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            ProfileAccountNotice(account: account)
            if env.session.accountKey == account {
                if isPrepared {
                    Section {
                        ForEach(0...5, id: \.self) { id in
                            Button { if !selected.insert(id).inserted { selected.remove(id) } } label: {
                                HStack {
                                    Text(id == 0 ? "Избранное" : ProfileListStatus(rawValue: id)?.title ?? "Список")
                                    Spacer()
                                    Image(systemName: selected.contains(id) ? "checkmark.square.fill" : "square")
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                    Section {
                        Button("Из всех моих списков") { selected.formUnion(0...5) }
                    } footer: {
                        Text("Используются для уведомлений из списков. Режим «По выбранным релизам» настраивается отдельно.")
                    }
                } else { ProfileResourceState(resource: resource, title: "Не удалось загрузить списки", retry: load) }
                ProfileSaveError(message: errorMessage ?? resource.errorMessage)
            }
        }
        .navigationTitle("Списки уведомлений").navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving || env.session.accountKey != account)
        .toolbar { ToolbarItem(placement: .confirmationAction) {
            Button("Выбрать") { Task { await save() } }.disabled(!isPrepared || isSaving)
        } }
        .task { await load() }
        .onChange(of: env.session.accountKey) { _, current in
            if account != current { resource.reset(); selected = []; isPrepared = false; errorMessage = nil }
        }
    }

    private func load() async {
        if let response = await resource.load({
            let response = try await env.session.sendAccountRequest(NotificationPreferenceEndpoints.my(), for: account)
            guard let values = response.statusPreferences, values.allSatisfy({ $0.statusID != nil }) else {
                throw AnixartError.decoding(message: "Сервер не вернул настройки списков", path: "profile/preference/notification/my")
            }
            return response
        }) {
            // Future IDs that have no checkbox must survive an ordinary edit.
            selected = Set((response.statusPreferences ?? []).compactMap(\.statusID))
            isPrepared = true
        }
    }

    private func save() async {
        guard isPrepared, !isSaving, env.session.accountKey == account else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await env.session.sendConfirmedAccountRequest(NotificationPreferenceEndpoints.editStatuses(selected), for: account)
            await env.session.refreshProfile(for: account)
            if env.session.accountKey == account { dismiss() }
        } catch { if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) } }
    }
}

private struct ProfileNotificationVoiceOptions: Decodable, Sendable {
    let types: [EpisodeType]
    let popularIDs: [Int]
    let selectedIDs: [Int]
}

@MainActor
struct ProfileNotificationVoicesSelector: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let account: ProfileAccountKey
    var releaseID: Int? = nil
    @State private var resource = ProfileResource<ProfileNotificationVoiceOptions>()
    @State private var selected = Set<Int>()
    @State private var query = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var filtered: [EpisodeType] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return (resource.value?.types ?? []).filter { query.isEmpty || ($0.name ?? "").localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            ProfileAccountNotice(account: account)
            if env.session.accountKey == account {
                if let options = resource.value {
                    Section {
                        Text(selected.isEmpty ? "От всех озвучек" : "От выбранных озвучек").foregroundStyle(.secondary)
                        Button("От всех озвучек") { selected.removeAll() }
                    }
                    if filtered.isEmpty { ProfileEmptySection(message: "Ой, ничего не нашлось!") }
                    else {
                        let popular = Set(options.popularIDs)
                        voiceGroup("Популярные", values: filtered.filter { popular.contains($0.id) })
                        voiceGroup("Остальные", values: filtered.filter { !popular.contains($0.id) })
                    }
                } else { ProfileResourceState(resource: resource, title: "Не удалось загрузить озвучки", retry: load) }
                ProfileSaveError(message: errorMessage ?? resource.errorMessage)
            }
        }
        .navigationTitle("Озвучки").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Поиск озвучек")
        .disabled(isSaving || env.session.accountKey != account)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Сбросить") { selected.removeAll() }.disabled(resource.value == nil) }
            ToolbarItem(placement: .confirmationAction) { Button("Выбрать") { Task { await save() } }.disabled(resource.value == nil || isSaving) }
        }
        .task { await load() }
        .onChange(of: env.session.accountKey) { _, current in
            if account != current { resource.reset(); selected = []; query = ""; errorMessage = nil }
        }
    }

    @ViewBuilder
    private func voiceGroup(_ title: String, values: [EpisodeType]) -> some View {
        if !values.isEmpty {
            Section(title) {
                ForEach(values) { type in
                    Button { if !selected.insert(type.id).inserted { selected.remove(type.id) } } label: {
                        HStack {
                            Text(type.name ?? "Озвучка").foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: selected.contains(type.id) ? "checkmark.square.fill" : "square")
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        if let options = await resource.load({
            if let releaseID {
                async let voices = env.session.sendAccountRequest(EpisodeEndpoints.types(releaseID: releaseID), for: account)
                async let preferences = env.session.sendAccountRequest(NotificationPreferenceEndpoints.releaseTypes(releaseID: releaseID), for: account)
                let (types, response) = try await (voices, preferences)
                guard let available = types.types, let selected = response.preferences,
                      selected.allSatisfy({ $0.type != nil }) else {
                    throw AnixartError.decoding(message: "Сервер не вернул настройки озвучек", path: "profile/preference/notification/release/type")
                }
                return ProfileNotificationVoiceOptions(types: available, popularIDs: [], selectedIDs: selected.compactMap { $0.type?.id })
            }
            async let voices = env.session.sendAccountRequest(ReleaseEndpoints.allTypes(), for: account)
            async let preferences = env.session.sendAccountRequest(NotificationPreferenceEndpoints.my(), for: account)
            let (types, response) = try await (voices, preferences)
            guard let available = types.types, let selected = response.typePreferences,
                  selected.allSatisfy({ $0.type != nil }) else {
                throw AnixartError.decoding(message: "Сервер не вернул настройки озвучек", path: "profile/preference/notification/my")
            }
            return ProfileNotificationVoiceOptions(types: available, popularIDs: types.popularTypeIds ?? [], selectedIDs: selected.compactMap { $0.type?.id })
        }) { selected = Set(options.selectedIDs) }
    }

    private func save() async {
        guard !isSaving, resource.value != nil, resource.errorMessage == nil, env.session.accountKey == account else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let endpoint = releaseID.map { NotificationPreferenceEndpoints.editReleaseTypes(releaseID: $0, ids: selected) }
                ?? NotificationPreferenceEndpoints.editTypes(selected)
            try await env.session.sendConfirmedAccountRequest(endpoint, for: account)
            await env.session.refreshProfile(for: account)
            if env.session.accountKey == account { dismiss() }
        } catch { if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) } }
    }
}

@MainActor
struct ProfileNotificationReleasesView: View {
    @Environment(AppEnvironment.self) private var env
    let account: ProfileAccountKey
    @State private var paginator: Paginator<Release>?
    var body: some View {
        List {
            ProfileAccountNotice(account: account)
            if env.session.accountKey == account, let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Выбранных релизов пока нет", emptyMessage: "Настройте озвучки для уведомлений на странице нужного релиза.") { release in
                    NavigationLink { ProfileNotificationVoicesSelector(account: account, releaseID: release.id) } label: { ReleaseRow(release: release) }
                }
            }
        }
        .navigationTitle("Выбранные релизы").navigationBarTitleDisplayMode(.inline)
        .task {
            guard env.session.accountKey == account else { return }
            let session = env.session
            if paginator == nil { paginator = Paginator { page in try await session.sendAccountRequest(NotificationPreferenceEndpoints.selectedReleases(page: page), for: account) } }
            await paginator?.loadFirstPageIfNeeded()
        }
        .refreshable { await paginator?.reload() }
        .onChange(of: env.session.accountKey) { _, current in if account != current { paginator = nil } }
    }
}
