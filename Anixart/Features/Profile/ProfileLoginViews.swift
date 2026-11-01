import SwiftUI
import AnixartKit

@MainActor
struct ProfileLoginEditorView: View {
    @Environment(AppEnvironment.self) private var env
    let profileID: Int
    @State private var info = ProfileResource<ChangeLoginInfoResponse>()
    @State private var preferences = ProfileResource<ProfilePreferenceResponse>()
    @State private var history: Paginator<ChangeLogin>?
    @State private var account: ProfileAccountKey?
    @State private var draft = ""
    @State private var suggestions: [String] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmsClear = false

    init(profileID: Int, account: ProfileAccountKey?) {
        self.profileID = profileID
        _account = State(initialValue: account)
    }

    private var mayChange: Bool {
        account?.profileID == profileID && env.session.accountKey == account
            && ProfileLoginAvailability.mayChange(info: info, preferences: preferences)
    }

    private var canSave: Bool {
        mayChange && !isSaving && env.session.accountKey == account
            && ProfileEditorRules.isValidLoginLength(draft) && draft != info.value?.login
    }

    var body: some View {
        List {
            ProfileAccountNotice(account: account)
            if env.session.accountKey == account, account != nil, let info = info.value {
                Section {
                    TextField("Новый никнейм", text: $draft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(!mayChange || isSaving)
                    Button { Task { await save() } } label: {
                        Label("Изменить", systemImage: "pencil").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canSave)
                } footer: {
                    if preferences.value?.isChangeLoginBanned == true {
                        Text("Смена никнейма ограничена до \(ProfileDate.text(preferences.value?.banChangeLoginExpires)).")
                    } else if info.isChangeAvailable != true {
                        Text("Следующая смена будет доступна \(ProfileDate.text(info.nextChangeAvailableAt)).")
                    } else {
                        Text("От 3 до 20 символов. Доступность никнейма проверяет сервер.")
                    }
                }
                if !suggestions.isEmpty {
                    Section("Доступные варианты") {
                        ForEach(suggestions, id: \.self) { login in
                            Button(login) { draft = login; suggestions = []; errorMessage = nil }
                        }
                    }
                }
                if let history {
                    Section("История изменений") {
                        PaginatedContent(paginator: history, emptyTitle: "Изменений нет") { change in
                            ProfileLoginHistoryRow(change: change)
                        }
                    }
                }
            } else if env.session.accountKey == account, account != nil {
                ProfileResourceState(resource: info, title: "Не удалось загрузить никнейм", retry: load)
            }
            ProfileSaveError(message: errorMessage ?? info.errorMessage ?? preferences.errorMessage)
            if info.value != nil, preferences.errorMessage != nil {
                Button("Повторить загрузку настроек") { Task { await load() } }
                    .disabled(isSaving || info.isLoading || preferences.isLoading)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Смена никнейма")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if history?.items.isEmpty == false {
                    Button { confirmsClear = true } label: { Image(systemName: "trash") }
                        .disabled(isSaving || env.session.accountKey != account)
                        .accessibilityLabel("Очистить историю никнейма")
                }
            }
        }
        .refreshable { if !isSaving { await load(); await history?.reload() } }
        .task {
            guard let account, account.profileID == profileID, env.session.accountKey == account else { return }
            await load()
            guard env.session.accountKey == account, !Task.isCancelled else { return }
            if history == nil {
                let session = env.session
                let id = profileID
                history = Paginator { page in try await session.sendAccountRequest(ProfileEndpoints.loginHistory(profileID: id, page: page), for: account) }
            }
            await history?.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.accountKey) { _, current in
            guard account != current else { return }
            info.reset()
            preferences.reset()
            history = nil
            draft = ""
            suggestions = []
            confirmsClear = false
            errorMessage = nil
        }
        .confirmationDialog("Очистить историю никнейма?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Очистить историю", role: .destructive) { Task { await clearHistory() } }
        } message: { Text("Эта история больше не будет видна в профиле. Действие нельзя отменить.") }
    }

    private func load() async {
        guard let account, account.profileID == profileID else { return }
        let session = env.session
        if let updated = await info.load({ try await session.sendAccountRequest(ProfilePreferenceEndpoints.loginInfo(), for: account) }),
           !isSaving {
            draft = updated.login ?? ""
        }
        await preferences.load { try await session.sendAccountRequest(ProfilePreferenceEndpoints.my(), for: account) }
    }

    private func save() async {
        guard canSave, let account else { return }
        let login = draft
        isSaving = true
        errorMessage = nil
        suggestions = []
        defer { isSaving = false }
        do {
            let check = try await env.session.sendViewerRequest(AuthEndpoints.checkLogin(login), for: account.viewerKey)
            try Task.checkCancellation()
            guard env.session.accountKey == account else { return }
            guard check.available == true else {
                suggestions = check.suggestedLogins ?? []
                errorMessage = "Этот никнейм недоступен. Выберите другой."
                return
            }
            try await env.session.sendConfirmedAccountRequest(ProfilePreferenceEndpoints.changeLogin(login), for: account)
            await load()
            await history?.reload()
            await env.session.refreshProfile(for: account)
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
        }
    }

    private func clearHistory() async {
        guard !isSaving, let account, account.profileID == profileID else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await env.session.sendConfirmedAccountRequest(ProfilePreferenceEndpoints.clearLoginHistory(), for: account)
            await history?.reload()
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
        }
    }
}

@MainActor
enum ProfileLoginAvailability {
    static func mayChange(info: ProfileResource<ChangeLoginInfoResponse>, preferences: ProfileResource<ProfilePreferenceResponse>) -> Bool {
        !info.isLoading && !preferences.isLoading && info.errorMessage == nil && preferences.errorMessage == nil
            && info.value?.code == AnixartStatus.successful && preferences.value?.code == AnixartStatus.successful
            && info.value?.isChangeAvailable == true && preferences.value?.isChangeLoginBanned == false
    }
}

@MainActor
struct ProfileLoginHistoryView: View {
    @Environment(AppEnvironment.self) private var env
    let profileID: Int
    @State private var viewer: ProfileViewerKey?
    @State private var paginator: Paginator<ChangeLogin>?

    init(profileID: Int, viewer: ProfileViewerKey? = nil) {
        self.profileID = profileID
        _viewer = State(initialValue: viewer)
    }

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Изменений нет") { ProfileLoginHistoryRow(change: $0) }
            }
        }
        .listStyle(.plain)
        .navigationTitle("История никнейма")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await paginator?.reload() }
        .task {
            if viewer == nil { viewer = env.session.viewerKey }
            guard let viewer, viewer == env.session.viewerKey else { return }
            if paginator == nil {
                let session = env.session
                let id = profileID
                paginator = Paginator { page in try await session.sendViewerRequest(ProfileEndpoints.loginHistory(profileID: id, page: page), for: viewer) }
            }
            await paginator?.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { paginator = nil }
        }
    }
}

struct ProfileLoginHistoryRow: View {
    let change: ChangeLogin
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(change.newLogin ?? "Никнейм").font(.ax(.body))
            Text(ProfileDate.text(change.timestamp)).font(.ax(.subheadline)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}
