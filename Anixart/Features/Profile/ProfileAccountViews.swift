import SwiftUI
import AnixartKit

@MainActor
struct ProfileEmailEditorView: View {
    @Environment(AppEnvironment.self) private var env
    let emailHint: String?
    let account: ProfileAccountKey?
    @State private var currentEmail = ""
    @State private var currentPassword = ""
    @State private var newEmail = ""
    @State private var code = ""
    @State private var pending: PendingEmail?
    @State private var isBusy = false
    @State private var hasChanged = false
    @State private var errorMessage: String?
    @State private var generation = 0

    /// Kept only in this screen's memory, never in preferences or logs. Resend
    /// uses the exact credentials that created the pending verification hash.
    private struct PendingEmail {
        let currentEmail: String
        let password: String
        let newEmail: String
        let hash: String
        var expires: Int?
    }

    private var canRequest: Bool {
        !isBusy && account != nil && env.session.accountKey == account && !currentPassword.isEmpty
            && !currentEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !newEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && currentEmail.caseInsensitiveCompare(newEmail) != .orderedSame
    }

    var body: some View {
        Form {
            ProfileAccountNotice(account: account)
            if account != nil, env.session.accountKey == account {
                if hasChanged {
                    Section { Label("Email изменён", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                } else if let pending {
                    Section("Подтверждение нового Email") {
                        Text("Код отправлен на \(pending.newEmail).")
                        TextField("Код из письма", text: $code)
                            .keyboardType(.numberPad).textContentType(.oneTimeCode)
                        Button("Подтвердить") { Task { await verify() } }
                            .disabled(ProfileEditorRules.emailVerificationCode(code) == nil)
                    } footer: {
                        if let expires = pending.expires, expires > 0 {
                            Text("Код действует до \(ProfileDate.dateTime(expires)).")
                        }
                    }
                    Section {
                        Button("Отправить код повторно") { Task { await resend() } }
                        Button("Использовать другой Email") { generation += 1; clearVerification() }
                    }
                } else {
                    Section("Текущие данные") {
                        emailField("Текущий Email", text: $currentEmail)
                        SecureField("Текущий пароль", text: $currentPassword).textContentType(.password)
                    } footer: {
                        if let emailHint { Text("Email учётной записи: \(emailHint)") }
                    }
                    Section("Новый Email") { emailField("Новый Email", text: $newEmail) }
                    Section {
                        Button("Продолжить") { Task { await request() } }.disabled(!canRequest)
                    } footer: { Text("На новый адрес придёт код подтверждения. Email изменится только после ввода кода.") }
                }
                if isBusy { ProgressView().frame(maxWidth: .infinity) }
                ProfileSaveError(message: errorMessage)
            }
        }
        .font(.ax(.body))
        .disabled(isBusy || account == nil || env.session.accountKey != account)
        .navigationTitle("Изменить Email")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onDisappear { generation += 1; clearVerification() }
        .onChange(of: env.session.accountKey) { _, current in
            guard account != current else { return }
            generation += 1
            clearVerification()
            currentEmail = ""
            newEmail = ""
            hasChanged = false
        }
    }

    private func emailField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text).keyboardType(.emailAddress).textContentType(.emailAddress)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
    }

    private func clearVerification() {
        pending = nil
        code = ""
        currentPassword = ""
        errorMessage = nil
    }

    private func request() async {
        guard canRequest, let account else { return }
        let oldEmail = currentEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = currentPassword
        let generation = self.generation
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let response = try await env.session.sendConfirmedAccountRequest(
                ProfilePreferenceEndpoints.changeEmail(currentEmail: oldEmail, currentPassword: password, newEmail: email), for: account
            )
            guard generation == self.generation else { return }
            guard let hash = response.hash, !hash.isEmpty else {
                throw AnixartError.decoding(message: "Сервер не вернул данные подтверждения", path: "profile/preference/email/change")
            }
            pending = PendingEmail(currentEmail: oldEmail, password: password, newEmail: email, hash: hash, expires: response.timestampExpires)
            currentPassword = ""
            code = ""
        } catch {
            if generation == self.generation, !ProfileRequestFailure.isCancellation(error) {
                errorMessage = Paginator<Release>.message(for: error)
            }
        }
    }

    private func resend() async {
        guard !isBusy, let pending, let account else { return }
        let generation = self.generation
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let response = try await env.session.sendConfirmedAccountRequest(
                ProfilePreferenceEndpoints.resendEmail(currentEmail: pending.currentEmail, currentPassword: pending.password,
                                                        newEmail: pending.newEmail, hash: pending.hash), for: account
            )
            guard generation == self.generation else { return }
            self.pending?.expires = response.timestampExpires ?? pending.expires
            code = ""
        } catch {
            if generation == self.generation, !ProfileRequestFailure.isCancellation(error) {
                errorMessage = Paginator<Release>.message(for: error)
            }
        }
    }

    private func verify() async {
        guard !isBusy, let pending, let account, let code = ProfileEditorRules.emailVerificationCode(code) else { return }
        let generation = self.generation
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await env.session.sendConfirmedAccountRequest(
                ProfilePreferenceEndpoints.verifyEmail(newEmail: pending.newEmail, code: code, hash: pending.hash), for: account
            )
            guard generation == self.generation else { return }
            hasChanged = true
            self.pending = nil
            self.code = ""
            currentPassword = ""
            await env.session.refreshProfile(for: account)
        } catch {
            if generation == self.generation, !ProfileRequestFailure.isCancellation(error) {
                errorMessage = Paginator<Release>.message(for: error)
            }
        }
    }
}

@MainActor
struct ProfilePasswordEditorView: View {
    @Environment(AppEnvironment.self) private var env
    let account: ProfileAccountKey?
    @State private var current = ""
    @State private var new = ""
    @State private var confirmation = ""
    @State private var isSaving = false
    @State private var confirmsChange = false
    @State private var updatedAccount: ProfileAccountKey?
    @State private var errorMessage: String?

    private var canSave: Bool {
        !isSaving && account != nil && env.session.accountKey == account && updatedAccount == nil
            && !current.isEmpty && !new.isEmpty && new == confirmation && new != current
    }

    private var isReplacingOwnToken: Bool {
        isSaving && account != nil && env.session.accountKey == nil
            && env.session.currentProfileID == account?.profileID
            && env.session.sessionRevision == account?.revision
    }

    var body: some View {
        Form {
            if !isReplacingOwnToken { ProfileAccountNotice(account: updatedAccount ?? account) }
            if (updatedAccount ?? account) != nil, env.session.accountKey == (updatedAccount ?? account) {
                if updatedAccount != nil {
                    Section { Label("Пароль изменён", systemImage: "checkmark.shield.fill").foregroundStyle(Theme.accent) }
                } else {
                    Section {
                        SecureField("Текущий пароль", text: $current).textContentType(.password)
                        SecureField("Новый пароль", text: $new).textContentType(.newPassword)
                        SecureField("Повторите новый пароль", text: $confirmation).textContentType(.newPassword)
                    } footer: { Text("Требования к паролю проверяет сервер. После изменения текущая сессия будет сохранена с новым токеном.") }
                    if !confirmation.isEmpty, new != confirmation {
                        Section { Text("Пароли не совпадают").foregroundStyle(.red) }
                    }
                    Section { Button("Изменить пароль") { confirmsChange = true }.disabled(!canSave) }
                }
                ProfileSaveError(message: errorMessage)
            }
            if isSaving { ProgressView().frame(maxWidth: .infinity) }
        }
        .font(.ax(.body))
        .disabled(isSaving || (updatedAccount ?? account) == nil || env.session.accountKey != (updatedAccount ?? account))
        .navigationTitle("Изменить пароль")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .confirmationDialog("Изменить пароль?", isPresented: $confirmsChange, titleVisibility: .visible) {
            Button("Изменить") { Task { await save() } }
        }
        .onDisappear { current = ""; new = ""; confirmation = "" }
        .onChange(of: env.session.accountKey) { _, currentAccount in
            guard (updatedAccount ?? account) != currentAccount else { return }
            current = ""
            new = ""
            confirmation = ""
            confirmsChange = false
            errorMessage = nil
        }
    }

    private func save() async {
        guard canSave, let account else { return }
        let oldPassword = current
        let newPassword = new
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            updatedAccount = try await env.session.changePassword(current: oldPassword, new: newPassword, for: account)
            current = ""
            new = ""
            confirmation = ""
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
        }
    }
}

@MainActor
struct ProfileServiceView: View {
    @Environment(AppEnvironment.self) private var env
    let service: ProfilePreferenceEndpoints.Service
    let account: ProfileAccountKey?
    @State private var resource = ProfileResource<ProfilePreferenceResponse>()
    @State private var isSaving = false
    @State private var confirmsUnbind = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            ProfileAccountNotice(account: account)
            if account != nil, env.session.accountKey == account {
                if let preferences = resource.value, let bound = preferences.isBound(to: service) {
                    Section {
                        Label(bound ? "Сервис привязан" : "Сервис не привязан", systemImage: bound ? "checkmark.circle.fill" : "link")
                        if bound {
                            Button("Отвязать \(service.title)", role: .destructive) { confirmsUnbind = true }
                                .disabled(isSaving)
                        } else { Button("Привязать \(service.title)") {}.disabled(true) }
                    } footer: {
                        if bound { Text("Вход в учётную запись через \(service.title) доступен, пока сервис привязан.") }
                        else { Text("Привязка пока недоступна: для iOS ещё не настроен безопасный вход через \(service.title). Ручной ввод токенов не используется.") }
                    }
                } else if resource.value != nil {
                    Section { Text("Сервер не вернул состояние привязки.").foregroundStyle(.secondary) }
                    Button("Обновить") { Task { await load() } }
                } else { ProfileResourceState(resource: resource, title: "Не удалось загрузить привязку", retry: load) }
                ProfileSaveError(message: errorMessage ?? resource.errorMessage)
            }
        }
        .font(.ax(.body))
        .navigationTitle(service.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await load() }
        .onChange(of: env.session.accountKey) { _, current in
            if account != current { resource.reset(); confirmsUnbind = false; errorMessage = nil }
        }
        .confirmationDialog("Отвязать \(service.title)?", isPresented: $confirmsUnbind, titleVisibility: .visible) {
            Button("Отвязать", role: .destructive) { Task { await unbind() } }
        } message: { Text("Вход через этот сервис станет недоступен. Убедитесь, что вы можете войти с Email и паролем.") }
    }

    private func load() async {
        guard let account else { return }
        await resource.load { try await env.session.sendAccountRequest(ProfilePreferenceEndpoints.my(), for: account) }
    }

    private func unbind() async {
        guard !isSaving, let account, resource.value?.isBound(to: service) == true else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await env.session.sendConfirmedAccountRequest(ProfilePreferenceEndpoints.unbind(service), for: account)
            await load()
            await env.session.refreshProfile(for: account)
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
        }
    }
}

@MainActor
struct ProfileDeletionView: View {
    @Environment(AppEnvironment.self) private var env
    let account: ProfileAccountKey?
    @State private var model: ProfileDeletionViewModel?
    @State private var password = ""
    @State private var confirmsRequest = false
    @State private var confirmsCancel = false

    private var isSaving: Bool { model?.isSaving == true }
    private var mayChange: Bool { model?.mayChange == true }

    var body: some View {
        Form {
            ProfileAccountNotice(account: account)
            if account != nil, env.session.accountKey == account {
                if let model, let status = model.resource.value {
                    if model.hasRequest {
                        Section("Удаление запрошено") {
                            LabeledContent("Запрос создан", value: ProfileDate.dateTime(status.requestedAt))
                            if let date = status.deleteAt, date > 0 {
                                LabeledContent("Удаление назначено", value: ProfileDate.dateTime(date))
                            } else { Text("Сервер пока не указал дату удаления.").foregroundStyle(.secondary) }
                        }
                        Section {
                            Button("Отменить удаление") { confirmsCancel = true }.disabled(!mayChange)
                        } footer: { Text("Отмена доступна, пока сервер ещё не завершил удаление.") }
                    } else if status.hasDeletionRequest == false {
                        Section {
                            Text("Вы можете запросить удаление аккаунта. Дату удаления назначает сервер. До завершения удаления запрос можно отменить.")
                            SecureField("Пароль учётной записи", text: $password).textContentType(.password)
                        }
                        Section {
                            Button("Запросить удаление", role: .destructive) { confirmsRequest = true }
                                .disabled(!mayChange || password.isEmpty)
                        }
                    } else {
                        Section { Text("Сервер не вернул статус запроса на удаление.").foregroundStyle(.secondary) }
                        Button("Обновить статус") { Task { await load() } }
                    }
                    if let notice = model.notice { Section { Text(notice).foregroundStyle(Theme.accent) } }
                    ProfileSaveError(message: model.errorMessage ?? model.resource.errorMessage)
                } else if let model {
                    ProfileResourceState(resource: model.resource, title: "Не удалось загрузить статус удаления", retry: load)
                    ProfileSaveError(message: model.errorMessage)
                } else { ProgressView().frame(maxWidth: .infinity) }
                if isSaving { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .font(.ax(.body))
        .disabled(isSaving || account == nil || env.session.accountKey != account)
        .navigationTitle("Удаление аккаунта")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { if !isSaving { await load() } }
        .task {
            if model == nil { model = ProfileDeletionViewModel(account: account, session: env.session) }
            await load()
        }
        .onDisappear { password = "" }
        .onChange(of: env.session.accountKey) { _, current in
            guard account != current else { return }
            model?.invalidate(for: current)
            password = ""
            confirmsRequest = false
            confirmsCancel = false
        }
        .confirmationDialog("Запросить удаление аккаунта?", isPresented: $confirmsRequest, titleVisibility: .visible) {
            Button("Запросить удаление", role: .destructive) { Task { await request() } }
        } message: { Text("Будет создан запрос на удаление аккаунта и связанных с ним данных. После завершения удаления восстановление может быть недоступно.") }
        .confirmationDialog("Отменить удаление аккаунта?", isPresented: $confirmsCancel, titleVisibility: .visible) {
            Button("Отменить удаление") { Task { await cancel() } }
        }
    }

    private func load() async {
        await model?.load()
    }

    private func request() async {
        guard let model, mayChange, !model.hasRequest, !password.isEmpty else { return }
        let draft = password
        defer { password = "" }
        await model.request(password: draft)
    }

    private func cancel() async {
        await model?.cancel()
    }
}
