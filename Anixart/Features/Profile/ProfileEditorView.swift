import SwiftUI
import PhotosUI
import UIKit
import AnixartKit

/// Account editing is a separate route. The gear still opens app-wide settings.
@MainActor
struct ProfileEditorView: View {
    @Environment(AppEnvironment.self) private var env
    let profileID: Int
    @State private var resource = ProfileResource<ProfilePreferenceResponse>()
    @State private var account: ProfileAccountKey?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(profileID: Int, account: ProfileAccountKey?) {
        self.profileID = profileID
        _account = State(initialValue: account)
    }

    private var preferences: ProfilePreferenceResponse? { resource.value }
    private var canEdit: Bool { account?.profileID == profileID && env.session.accountKey == account }

    var body: some View {
        List {
            ProfileAccountNotice(account: account)
            if canEdit, let preferences {
                Section {
                    NavigationLink {
                        ProfilePhotoEditorView(kind: .avatar, profileID: profileID, account: account)
                    } label: {
                        HStack {
                            ProfileEditorRow(title: "Изменить фото", subtitle: "Фото вашего профиля")
                            Spacer()
                            Avatar(url: AnixartURL.image(preferences.avatar), size: 44)
                        }
                    }
                    NavigationLink {
                        ProfilePhotoEditorView(kind: .cover, profileID: profileID, account: account)
                    } label: {
                        ProfileEditorRow(title: "Изменить обложку", subtitle: "Обложка доступна с 3-го уровня репутации")
                    }
                    NavigationLink {
                        ProfileStatusEditorView(initialStatus: preferences.status ?? "", account: account)
                    } label: {
                        ProfileEditorRow(title: "Изменить статус", subtitle: preferences.status?.isEmpty == false ? preferences.status : "Расскажите немного о себе")
                    }
                    NavigationLink { ProfileLoginEditorView(profileID: profileID, account: account) } label: {
                        ProfileEditorRow(title: "Изменить никнейм", subtitle: env.session.profile?.displayLogin)
                    }
                    NavigationLink { ProfileBadgesView(profileID: profileID, selecting: true, viewer: account?.viewerKey) } label: {
                        ProfileEditorRow(title: "Изменить значок", subtitle: preferences.badge?.name ?? "Значок не установлен")
                    }
                    NavigationLink { ProfileSocialEditorView(profileID: profileID, account: account) } label: {
                        ProfileEditorRow(title: "Мои социальные сети", subtitle: "Укажите ссылки на свои страницы в соц. сетях")
                    }
                } header: { header("Профиль") }
                .disabled(!canEdit)

                Section {
                    NavigationLink { ProfileHiddenChannelsView(account: account) } label: { Text("Скрытые каналы") }
                } header: { header("Лента") }
                .disabled(!canEdit)

                Section {
                    privacyRow("Кто видит мою статистику, оценки и историю просмотра", field: .statistics, value: preferences.privacyStats)
                    privacyRow("Кто видит в профиле мои комментарии, коллекции, видео и друзей", field: .counts, value: preferences.privacyCounts)
                    privacyRow("Кто видит мои социальные сети", field: .social, value: preferences.privacySocial)
                    Menu {
                        ForEach(FriendRequestPrivacy.allCases) { permission in
                            Button { Task { await setPrivacy(.friendRequests, value: permission.rawValue) } } label: {
                                if preferences.privacyFriendRequests == permission.rawValue {
                                    Label(permission.title, systemImage: "checkmark")
                                } else { Text(permission.title) }
                            }
                        }
                    } label: {
                        ProfileEditorRow(title: "Кто может отправлять мне заявки в друзья",
                                         subtitle: FriendRequestPrivacy(rawValue: preferences.privacyFriendRequests ?? 0)?.title)
                    }
                    NavigationLink { ProfileBlockListView(account: account) } label: {
                        ProfileEditorRow(title: "Блоклист", subtitle: "Пользователи, которым запрещён доступ к вашей странице")
                    }
                } header: { header("Приватность") }
                .disabled(isSaving || !canEdit)

                Section {
                    NavigationLink { ProfileHealthView(account: account, channelID: preferences.channelId) } label: {
                        ProfileEditorRow(title: "Здоровье аккаунта", subtitle: "История нарушений и ограничений")
                    }
                    NavigationLink { ProfileEmailEditorView(emailHint: preferences.emailHint, account: account) } label: {
                        ProfileEditorRow(title: "Изменить Email", subtitle: preferences.emailHint ?? "Email учётной записи")
                    }
                    NavigationLink { ProfilePasswordEditorView(account: account) } label: {
                        ProfileEditorRow(title: "Изменить пароль", subtitle: "Пароль учётной записи")
                    }
                } header: { header("Безопасность") }
                .disabled(!canEdit)

                Section {
                    ForEach(ProfilePreferenceEndpoints.Service.allCases) { service in
                        NavigationLink { ProfileServiceView(service: service, account: account) } label: {
                            HStack {
                                Text(service.title)
                                Spacer()
                                Image(systemName: isBound(service, preferences) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isBound(service, preferences) ? Theme.accent : Color.secondary)
                            }
                        }
                    }
                } header: { header("Привязка к сервисам") }
                .disabled(!canEdit)

                Section {
                    NavigationLink { ProfileDeletionView(account: account) } label: {
                        ProfileEditorRow(title: "Удаление аккаунта", subtitle: "Запросить удаление или отменить ранее созданный запрос")
                    }
                } header: { header("Аккаунт") }
                .disabled(!canEdit)
                ProfileSaveError(message: resource.errorMessage)
            } else if canEdit {
                ProfileResourceState(resource: resource, title: "Не удалось загрузить настройки", retry: load)
            }
        }
        .font(.ax(.body))
        .listStyle(.plain)
        .navigationTitle("Редактирование")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { if !isSaving { await load() } }
        .task(id: env.session.profileRevision) { if !isSaving { await load() } }
        .onChange(of: env.session.accountKey) { _, current in
            if account != current { resource.reset(); errorMessage = nil }
        }
        .alert("Не удалось сохранить", isPresented: Binding(get: { preferences != nil && errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Понятно", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.ax(.subheadline, .medium)).foregroundStyle(Theme.accent).textCase(nil)
    }

    private func privacyRow(_ title: String, field: ProfilePreferenceEndpoints.PrivacyField, value: Int?) -> some View {
        Menu {
            ForEach(ProfilePrivacy.allCases) { permission in
                Button { Task { await setPrivacy(field, value: permission.rawValue) } } label: {
                    if value == permission.rawValue { Label(permission.title, systemImage: "checkmark") }
                    else { Text(permission.title) }
                }
            }
        } label: {
            ProfileEditorRow(title: title, subtitle: ProfilePrivacy(rawValue: value ?? 0)?.title)
        }
        .foregroundStyle(.primary)
    }

    private func isBound(_ service: ProfilePreferenceEndpoints.Service, _ preferences: ProfilePreferenceResponse) -> Bool {
        preferences.isBound(to: service) == true
    }

    private func load() async {
        guard canEdit, let account else { return }
        await resource.load { try await env.session.sendAccountRequest(ProfilePreferenceEndpoints.my(), for: account) }
    }

    private func setPrivacy(_ field: ProfilePreferenceEndpoints.PrivacyField, value: Int) async {
        guard canEdit, !isSaving, let account else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await env.session.sendConfirmedAccountRequest(ProfilePreferenceEndpoints.editPrivacy(field, permission: value), for: account)
            await load()
            await env.session.refreshProfile(for: account)
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
        }
    }
}

struct ProfileEditorRow: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.ax(.body)).foregroundStyle(.primary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.ax(.subheadline)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor
struct ProfileStatusEditorView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let account: ProfileAccountKey?
    @State private var draft: String
    private let original: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(initialStatus: String, account: ProfileAccountKey?) {
        self.account = account
        original = initialStatus
        _draft = State(initialValue: initialStatus)
    }

    var body: some View {
        Form {
            ProfileAccountNotice(account: account)
            if account != nil, env.session.accountKey == account {
                Section {
                    TextField("Расскажите немного о себе", text: $draft, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: draft) { _, value in
                            if !ProfileEditorRules.isValidStatus(value) { draft = ProfileEditorRules.limitedStatus(value) }
                        }
                } footer: { Text("\(draft.utf16.count) / \(ProfileEditorRules.statusLimit)") }
                ProfileSaveError(message: errorMessage)
            }
        }
        .navigationTitle("Статус")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .confirmationAction) {
            Button("Сохранить") { Task { await save() } }
                .disabled(isSaving || draft == original || !ProfileEditorRules.isValidStatus(draft) || account == nil || env.session.accountKey != account)
        } }
        .disabled(isSaving || account == nil || env.session.accountKey != account)
        .onChange(of: env.session.accountKey) { _, current in
            if account != current { draft = ""; errorMessage = nil }
        }
    }

    private func save() async {
        guard !isSaving, ProfileEditorRules.isValidStatus(draft), let account else { return }
        let status = draft
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await env.session.sendConfirmedAccountRequest(ProfilePreferenceEndpoints.editStatus(status), for: account)
            await env.session.refreshProfile(for: account)
            if env.session.accountKey == account, !Task.isCancelled { dismiss() }
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
        }
    }
}

@MainActor
struct ProfileSocialEditorView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let profileID: Int
    @State private var account: ProfileAccountKey?
    @State private var resource = ProfileResource<ProfileSocialResponse>()
    @State private var draft = SocialPagesEditRequest()
    @State private var original: SocialPagesEditRequest?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(profileID: Int, account: ProfileAccountKey?) {
        self.profileID = profileID
        _account = State(initialValue: account)
    }

    var body: some View {
        Form {
            ProfileAccountNotice(account: account)
            if account != nil, env.session.accountKey == account {
            if original != nil {
                Section("ВКонтакте") { socialField("Ссылка на страницу", text: $draft.vkPage) }
                Section("Telegram") { socialField("Ссылка на страницу", text: $draft.tgPage) }
                Section("Discord") { socialField("Имя пользователя или ссылка", text: $draft.discordPage) }
                Section("TikTok") { socialField("Ссылка на страницу", text: $draft.ttPage) }
                // Instagram is hidden by Android, but its stored value must survive saving.
            } else { ProfileResourceState(resource: resource, title: "Не удалось загрузить социальные сети", retry: load) }
            ProfileSaveError(message: errorMessage)
            }
        }
        .navigationTitle("Мои социальные сети")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .confirmationAction) {
            Button("Сохранить") { Task { await save() } }
                .disabled(original == nil || draft == original || isSaving || env.session.accountKey != account)
        } }
        .disabled(isSaving || account == nil || env.session.accountKey != account)
        .task { if original == nil { await load() } }
        .onChange(of: env.session.accountKey) { _, current in
            guard account != current else { return }
            resource.reset()
            draft = SocialPagesEditRequest()
            original = nil
            errorMessage = nil
        }
    }

    private func socialField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text).textInputAutocapitalization(.never).autocorrectionDisabled()
            .keyboardType(.URL)
    }

    private func load() async {
        guard let account, account.profileID == profileID else { return }
        if let response = await resource.load({ try await env.session.sendAccountRequest(ProfilePreferenceEndpoints.social(), for: account) }) {
            draft = SocialPagesEditRequest(response)
            original = draft
        }
    }

    private func save() async {
        guard original != nil, !isSaving, let account, account.profileID == profileID else { return }
        let pages = draft
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await env.session.sendConfirmedAccountRequest(ProfilePreferenceEndpoints.editSocial(pages), for: account)
            await env.session.refreshProfile(for: account)
            if env.session.accountKey == account, !Task.isCancelled { dismiss() }
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
        }
    }
}

@MainActor
struct ProfilePhotoEditorView: View {
    enum Kind: Equatable { case avatar, cover }
    @Environment(AppEnvironment.self) private var env
    let kind: Kind
    let profileID: Int
    let account: ProfileAccountKey?
    @State private var resource = ProfileResource<ProfilePreferenceResponse>()
    @State private var blog = ProfileResource<ChannelResponse>()
    @State private var currentURL: URL?
    @State private var selected: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var isBusy = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    private var preferences: ProfilePreferenceResponse? { resource.value }

    private var mayEdit: Bool {
        guard let preferences, account?.profileID == profileID, env.session.accountKey == account else { return false }
        if kind == .avatar { return preferences.isChangeAvatarBanned != true }
        return (env.session.profile?.ratingScore ?? 0) >= ProfileEditorRules.minimumCoverReputation && preferences.channelId != nil
    }

    var body: some View {
        Form {
            ProfileAccountNotice(account: account)
            if account != nil, env.session.accountKey == account {
            Section {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260)
                        .frame(maxWidth: .infinity)
                } else {
                    CachedAsyncImage(url: currentURL, maxPixelSize: 1000) { $0.resizable().scaledToFit() } placeholder: {
                        Image(systemName: kind == .avatar ? "person.crop.circle" : "photo")
                            .font(.system(size: 64)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).frame(height: 220)
                }
                if mayEdit {
                    PhotosPicker(selection: $selected, matching: .images) {
                        Label("Выбрать фото", systemImage: "photo.on.rectangle")
                    }
                    Button("Сохранить") { Task { await upload() } }.disabled(image == nil)
                    if currentURL != nil {
                        Button("Удалить", role: .destructive) { isConfirmingDelete = true }
                    }
                } else if let preferences {
                    if kind == .avatar, preferences.isChangeAvatarBanned == true {
                        Text("Возможность смены фото временно ограничена.\n\(ProfileDate.text(preferences.banChangeAvatarExpires))")
                    } else {
                        Text("Обложка доступна с 3-го уровня репутации.")
                    }
                } else { ProfileResourceState(resource: resource, title: "Не удалось загрузить фото", retry: load) }
            }
            ProfileSaveError(message: errorMessage ?? resource.errorMessage ?? blog.errorMessage)
            }
        }
        .navigationTitle(kind == .avatar ? "Фото профиля" : "Обложка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .disabled(isBusy || account == nil || env.session.accountKey != account)
        .task { await load() }
        .task(id: selected) {
            guard let selected, let account, env.session.accountKey == account else { return }
            do {
                guard let data = try await selected.loadTransferable(type: Data.self), let decoded = UIImage(data: data) else {
                    throw AnixartError.decoding(message: "Не удалось прочитать изображение", path: "photos")
                }
                guard !Task.isCancelled, env.session.accountKey == account, selected == self.selected else { return }
                image = decoded
            } catch {
                if env.session.accountKey == account, selected == self.selected, !ProfileRequestFailure.isCancellation(error) {
                    errorMessage = Paginator<Release>.message(for: error)
                }
            }
        }
        .onChange(of: env.session.accountKey) { _, current in
            guard account != current else { return }
            resource.reset()
            blog.reset()
            currentURL = nil
            image = nil
            selected = nil
            isConfirmingDelete = false
            errorMessage = nil
        }
        .confirmationDialog("Удалить \(kind == .avatar ? "фото профиля" : "обложку")?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { await delete() } }
        }
    }

    private func load() async {
        guard let account, account.profileID == profileID else { return }
        if let preferences = await resource.load({ try await env.session.sendAccountRequest(ProfilePreferenceEndpoints.my(), for: account) }) {
            if kind == .avatar { currentURL = AnixartURL.image(preferences.avatar) }
            else if mayEdit, let expectedID = preferences.channelId {
                if let response = await blog.load({
                    let response = try await env.session.sendAccountRequest(ChannelEndpoints.blog(profileID: profileID), for: account)
                    guard response.channel?.id == expectedID else {
                        throw AnixartError.decoding(message: "Ответ не содержит канал профиля", path: "channel/blog/\(profileID)")
                    }
                    return response
                }) { currentURL = AnixartURL.image(response.channel?.cover) }
            }
        }
    }

    private func upload() async {
        guard mayEdit, !isBusy, let image, let account else { return }
        guard let data = ProfileImagePreparation.jpeg(image, avatar: kind == .avatar) else {
            errorMessage = "Не удалось подготовить изображение"; return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            if kind == .avatar {
                let response = try await env.session.sendConfirmedAccountRequest(ProfilePreferenceEndpoints.editAvatar(jpeg: data), for: account)
                currentURL = AnixartURL.image(response.avatar)
            } else if let channelID = preferences?.channelId {
                let response = try await env.session.sendConfirmedAccountRequest(ChannelEndpoints.uploadCover(channelID: channelID, jpeg: data), for: account)
                currentURL = AnixartURL.image(response.url)
            }
            self.image = nil
            selected = nil
            errorMessage = nil
            await load()
            await env.session.refreshProfile(for: account)
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
        }
    }

    private func delete() async {
        guard mayEdit, !isBusy, let account else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            if kind == .avatar { try await env.session.sendConfirmedAccountRequest(ProfilePreferenceEndpoints.deleteAvatar(), for: account) }
            else if let id = preferences?.channelId { try await env.session.sendConfirmedAccountRequest(ChannelEndpoints.deleteCover(channelID: id), for: account) }
            image = nil; selected = nil
            currentURL = nil
            await load()
            await env.session.refreshProfile(for: account)
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
        }
    }
}

enum ProfileImagePreparation {
    static func jpeg(_ image: UIImage, avatar: Bool) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return nil }
        let side = min(size.width, size.height)
        let source = avatar ? CGSize(width: side, height: side) : size
        let scale = min(1, (avatar ? 800.0 : 1600.0) / max(source.width, source.height))
        let target = CGSize(width: source.width * scale, height: source.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            let offset = avatar ? CGPoint(x: -(size.width - side) * scale / 2, y: -(size.height - side) * scale / 2) : .zero
            image.draw(in: CGRect(origin: offset, size: CGSize(width: size.width * scale, height: size.height * scale)))
        }.jpegData(compressionQuality: 0.9)
    }
}

struct ProfileSaveError: View {
    var message: String?
    var body: some View {
        if let message { Section { Text(message).font(.ax(.subheadline)).foregroundStyle(.red) } }
    }
}

enum ProfileDate {
    static func text(_ timestamp: Int?) -> String {
        guard let timestamp, timestamp > 0 else { return "—" }
        return Format.date(Date(timeIntervalSince1970: TimeInterval(timestamp))) ?? "—"
    }

    static func dateTime(_ timestamp: Int?) -> String {
        guard let timestamp, timestamp > 0 else { return "—" }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
            .formatted(.dateTime.day().month(.wide).year().hour().minute().locale(Locale(identifier: "ru_RU")))
    }
}
