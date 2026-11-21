import SwiftUI
import AnixartKit

/// Settings, reached from the gear on Главная.
///
/// Laid out like the Android beta 3 settings: rounded groups of cards, each with a round
/// icon, a title and a line saying what is inside. Only implemented subsystems are
/// exposed; Android's ad and import/export cards have no counterpart here, and the
/// iOS-only items (haptics, Kodik diagnostics, request compatibility) sit beside them.
@MainActor
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirmingSignOut = false
    @State private var signOutAccount: ProfileAccountKey?

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        if let label = info?["AnixartVersionLabel"] as? String { return "Версия \(label) · Сборка \(build) (\(short))" }
        return "Версия \(short) · Сборка \(build)"
    }

    private var accountRows: [SettingsRowModel] {
        if let profile = env.session.profile {
            return [
                SettingsRowModel(icon: "person.fill", title: "Аккаунт", subtitle: "Вы вошли как \(profile.displayLogin)", kind: .action {}),
                SettingsRowModel(icon: "rectangle.portrait.and.arrow.right", title: "Выйти из аккаунта", subtitle: nil,
                                 kind: .action { signOutAccount = env.session.accountKey; isConfirmingSignOut = true }, isDestructive: true)
            ]
        }
        return [
            SettingsRowModel(icon: "person.crop.circle", title: "Войти", subtitle: "Списки, закладки и комментарии",
                             kind: .action { dismiss(); env.session.promptSignIn() })
        ]
    }

    private var appRows: [SettingsRowModel] {
        [
            SettingsRowModel(icon: "bell.fill", title: "Уведомления", subtitle: "Новые серии и релизы, записи, комментарии",
                             kind: .destination(AnyView(ProfileNotificationPreferencesView(account: env.session.accountKey)))),
            SettingsRowModel(icon: "tray.fill", title: "Все уведомления", subtitle: "Список полученных уведомлений",
                             kind: .destination(AnyView(NotificationsView()))),
            SettingsRowModel(icon: "play.fill", title: "Воспроизведение", subtitle: "Видеоплеер, качество, автовоспроизведение",
                             kind: .destination(AnyView(DevicePlaybackSettingsView()))),
            SettingsRowModel(icon: "arrow.down.to.line", title: "Загрузки", subtitle: "Качество, сеть, скачанные серии",
                             kind: .destination(AnyView(DownloadsView()))),
            SettingsRowModel(icon: "paintpalette.fill", title: "Внешний вид", subtitle: "Тема, цвета, шрифт, вкладки по умолчанию",
                             kind: .destination(AnyView(DeviceAppearanceSettingsView()))),
            SettingsRowModel(icon: "internaldrive.fill", title: "Данные и память", subtitle: "Кэш изображений и его очистка",
                             kind: .destination(AnyView(DeviceDataSettingsView()))),
            SettingsRowModel(icon: "waveform", title: "Вибро-отклик", subtitle: "Сила и события, которые откликаются",
                             kind: .destination(AnyView(DeviceHapticsSettingsView()))),
            SettingsRowModel(icon: "ellipsis", title: "Дополнительно", subtitle: "Продолжить просмотр, экономия ресурсов",
                             kind: .destination(AnyView(DeviceAdditionalSettingsView())))
        ]
    }

    private var infoRows: [SettingsRowModel] {
        let web = AnixartEnvironment.webBaseURL
        return [
            SettingsRowModel(icon: "questionmark", title: "Помощь", subtitle: "Ответы на частые вопросы",
                             kind: .url(web.appendingPathComponent("faq"))),
            SettingsRowModel(icon: "checkmark.shield.fill", title: "Правила сообщества", subtitle: "Правила общения и публикаций",
                             kind: .url(web.appendingPathComponent("rules"))),
            SettingsRowModel(icon: "doc.text.fill", title: "Пользовательское соглашение", subtitle: "Условия использования",
                             kind: .url(web.appendingPathComponent("terms"))),
            SettingsRowModel(icon: "arrow.down.app.fill", title: "Проверить обновления", subtitle: "Новые сборки приложения на GitHub",
                             kind: .url(URL(string: "https://github.com/yukinine-dev/anixart-ios/releases")!))
        ]
    }

    // Kodik carries almost every voice-over, and what its page does can only be measured on
    // a real device -- four runs in a simulator saw nothing at all.
    private var diagnosticsRows: [SettingsRowModel] {
        [
            SettingsRowModel(icon: "stethoscope", title: "Проверить Kodik", subtitle: "Что отдаёт страница плеера на этом устройстве",
                             kind: .destination(AnyView(KodikDiagnosticsView()))),
            SettingsRowModel(icon: "arrow.left.arrow.right", title: "Совместимость запросов", subtitle: "Переключатели для поиска причины отказов сервера",
                             kind: .destination(AnyView(RequestCompatibilityView())))
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    SettingsGroup(rows: accountRows)
                    SettingsGroup(rows: appRows)
                    SettingsGroup(rows: infoRows)
                    SettingsGroup(rows: diagnosticsRows)

                    VStack(spacing: 8) {
                        Text(versionText).font(.ax(.subheadline)).foregroundStyle(.secondary).monospacedDigit()
                        Text("Неофициальный клиент Anixart для iOS. Приложение не связано с "
                             + "командой Anixart и использует её общедоступный API.")
                            .font(.ax(.caption)).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
                }
                .padding(.horizontal)
                .padding(.top, 8)
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
                    AppHaptics.shared.play(.destructiveConfirm)
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
