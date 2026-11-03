import SwiftUI
import AnixartKit

/// Settings, reached from the gear on Главная.
///
/// Only implemented subsystems are exposed. Android-only players, modded ads,
/// import/export and downloads are not represented by decorative settings.
@MainActor
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirmingSignOut = false
    @State private var signOutAccount: ProfileAccountKey?

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Аккаунт") {
                    if let profile = env.session.profile {
                        HStack {
                            Text("Вы вошли как")
                            Spacer()
                            Text(profile.displayLogin).foregroundStyle(.secondary)
                        }
                        Button("Выйти", role: .destructive) { signOutAccount = env.session.accountKey; isConfirmingSignOut = true }
                    } else {
                        Button("Войти") {
                            dismiss()
                            env.session.promptSignIn()
                        }
                    }
                }

                Section("Уведомления") {
                    NavigationLink { ProfileNotificationPreferencesView(account: env.session.accountKey) } label: {
                        Label("Настройки уведомлений", systemImage: "bell.badge")
                    }
                    NavigationLink {
                        NotificationsView()
                    } label: {
                        Label("Уведомления", systemImage: "bell")
                    }
                }

                Section("Приложение") {
                    NavigationLink { DevicePlaybackSettingsView() } label: { Label("Воспроизведение", systemImage: "play.rectangle") }
                    NavigationLink { DeviceAppearanceSettingsView() } label: { Label("Внешний вид", systemImage: "paintpalette") }
                    NavigationLink { DeviceDataSettingsView() } label: { Label("Управление данными", systemImage: "internaldrive") }
                    NavigationLink { DeviceAdditionalSettingsView() } label: { Label("Дополнительно", systemImage: "slider.horizontal.3") }
                }

                Section("Правовая информация") {
                    Link(destination: AnixartEnvironment.webBaseURL.appendingPathComponent("faq")) {
                        Label("Помощь / FAQ", systemImage: "questionmark.circle")
                    }
                    Link(destination: AnixartEnvironment.webBaseURL.appendingPathComponent("rules")) {
                        Label("Правила сообщества", systemImage: "shield")
                    }
                    Link(destination: AnixartEnvironment.webBaseURL.appendingPathComponent("terms")) {
                        Label("Пользовательское соглашение", systemImage: "doc.text")
                    }
                }

                // Kodik carries almost every voice-over, and what its page does
                // can only be measured on a real device -- four runs in a
                // simulator saw nothing at all.
                Section("Диагностика") {
                    NavigationLink {
                        KodikDiagnosticsView()
                    } label: {
                        Label("Проверить Kodik", systemImage: "stethoscope")
                    }
                }

                Section {
                    HStack {
                        Text("Версия")
                        Spacer()
                        Text(appVersion).foregroundStyle(.secondary).monospacedDigit()
                    }
                } footer: {
                    Text("Неофициальный клиент Anixart для iOS. Приложение не связано с "
                         + "командой Anixart и использует её общедоступный API.")
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .confirmationDialog(
                "Выйти из аккаунта?",
                isPresented: $isConfirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Выйти", role: .destructive) {
                    Task {
                        guard let signOutAccount, env.session.accountKey == signOutAccount else { return }
                        await env.session.signOut()
                        dismiss()
                    }
                }
            }
        }
        .anixartAppearance()
        .anixartColorScheme()
    }
}
