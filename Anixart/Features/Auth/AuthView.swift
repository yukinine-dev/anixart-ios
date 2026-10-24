import SwiftUI
import AnixartKit

/// Sign-in and registration.
///
/// Registration is two steps on Anixart: `auth/signUp` returns a `hash` and mails a
/// code, then `auth/verify` exchanges hash + code for a token. The same `verify`
/// call finishes social registration, which is why it takes every credential field.
@MainActor
struct AuthView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .signIn
    @State private var login = ""
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var pendingHash: String?
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    enum Mode: Hashable {
        case signIn, signUp, restore
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Режим", selection: $mode) {
                    Text("Вход").tag(Mode.signIn)
                    Text("Регистрация").tag(Mode.signUp)
                    Text("Сброс пароля").tag(Mode.restore)
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, _ in resetFlow() }

                if pendingHash == nil {
                    credentialFields
                } else {
                    codeField
                }

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
                if let infoMessage {
                    Text(infoMessage).font(.footnote).foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if isBusy { ProgressView() } else { Text(primaryActionTitle).fontWeight(.semibold) }
                            Spacer()
                        }
                    }
                    .disabled(isBusy || !canSubmit)
                }

                Section {
                    Text(
                        "Приложение использует официальное API Anixart. "
                        + "Вход через VK, Google, Telegram и Яндекс требует SDK этих сервисов "
                        + "и пока не подключён — используйте никнейм и пароль."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Аккаунт")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(isBusy)
    }

    // MARK: - Fields

    @ViewBuilder
    private var credentialFields: some View {
        Section {
            switch mode {
            case .signIn:
                TextField("Никнейм или email", text: $login)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Пароль", text: $password)
                    .textContentType(.password)

            case .signUp:
                TextField("Никнейм", text: $login)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Пароль", text: $password)
                    .textContentType(.newPassword)

            case .restore:
                TextField("Никнейм или email", text: $login)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } footer: {
            if mode == .signUp {
                Text("На указанный email придёт код подтверждения.")
            }
        }
    }

    private var codeField: some View {
        Section {
            TextField("Код из письма", text: $code)
                .keyboardType(.numberPad)
            if mode == .restore {
                SecureField("Новый пароль", text: $password)
                    .textContentType(.newPassword)
            }
        } footer: {
            Text("Код отправлен на \(mode == .signUp ? email : login).")
        }
    }

    private var primaryActionTitle: String {
        if pendingHash != nil { return "Подтвердить" }
        switch mode {
        case .signIn: return "Войти"
        case .signUp: return "Зарегистрироваться"
        case .restore: return "Отправить код"
        }
    }

    private var canSubmit: Bool {
        if pendingHash != nil {
            return code.count >= 4 && (mode != .restore || password.count >= 6)
        }
        switch mode {
        case .signIn:
            return !login.isEmpty && !password.isEmpty
        case .signUp:
            return !login.isEmpty && email.contains("@") && password.count >= 6
        case .restore:
            return !login.isEmpty
        }
    }

    // MARK: - Actions

    private func submit() async {
        isBusy = true
        errorMessage = nil
        infoMessage = nil

        do {
            if let hash = pendingHash {
                try await confirm(hash: hash)
            } else {
                try await begin()
            }
        } catch {
            errorMessage = Paginator<Release>.message(for: error)
        }

        isBusy = false
    }

    private func begin() async throws {
        switch mode {
        case .signIn:
            try await env.session.signIn(login: login, password: password)
            dismiss()

        case .signUp:
            let response = try await env.client.send(
                AuthEndpoints.signUp(login: login, email: email, password: password)
            )
            guard let hash = response.hash else {
                throw AnixartError.api(code: AnixartStatus.failed, path: "auth/signUp")
            }
            pendingHash = hash
            infoMessage = "Код отправлен. Проверьте почту."

        case .restore:
            let response = try await env.client.send(AuthEndpoints.restore(data: login))
            guard let hash = response.hash else {
                throw AnixartError.api(code: AnixartStatus.failed, path: "auth/restore")
            }
            pendingHash = hash
            password = ""
            infoMessage = "Код отправлен. Укажите новый пароль."
        }
    }

    private func confirm(hash: String) async throws {
        switch mode {
        case .signUp:
            try await env.session.verify(
                login: login,
                email: email,
                password: password,
                hash: hash,
                code: code
            )
            dismiss()

        case .restore:
            let response = try await env.client.send(
                AuthEndpoints.restoreVerify(data: login, password: password, hash: hash, code: code)
            )
            guard response.profileToken?.token != nil else {
                throw AnixartError.api(code: AnixartStatus.failed, path: "auth/restore/verify")
            }
            // The restore flow returns a usable session, so sign in with the new password.
            try await env.session.signIn(login: login, password: password)
            dismiss()

        case .signIn:
            break
        }
    }

    private func resetFlow() {
        pendingHash = nil
        code = ""
        errorMessage = nil
        infoMessage = nil
    }
}
