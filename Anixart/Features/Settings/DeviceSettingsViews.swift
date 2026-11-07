import SwiftUI

enum DeviceAppearancePreferenceKey {
    static let colorScheme = "appearance.colorScheme"
    static let defaultBookmarks = "appearance.defaultBookmarks"
    static let resourceSaving = "appearance.resourceSaving"
    static let continueWatching = "appearance.continueWatching"
    static let continueWatchingDismissed = "appearance.continueWatching.dismissed"
    static let visualTheme = "appearance.visualTheme"
    static let accent = "appearance.accent"
}

enum AppColorSchemePreference: String, CaseIterable, Identifiable {
    case system, light, dark, lowPower
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "По умолчанию"
        case .light: return "Выключена"
        case .dark: return "Включена"
        case .lowPower: return "В режиме энергосбережения"
        }
    }
    func colorScheme(lowPower: Bool) -> ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        case .lowPower: return lowPower ? .dark : .light
        }
    }
}

@MainActor
struct DevicePlaybackSettingsView: View {
    @State private var preferences = PlaybackPreferences()
    private var player: Binding<String> {
        Binding(get: { preferences.alwaysAsk ? "ask" : preferences.choice.rawValue }, set: { value in
            if value == "ask" { preferences.save(choice: preferences.choice, alwaysAsk: true) }
            else if let choice = PlayerChoice(rawValue: value) { preferences.save(choice: choice, alwaysAsk: false) }
        })
    }
    var body: some View {
        Form {
            Section {
                Picker("Видеоплеер", selection: player) {
                    Text("Спрашивать").tag("ask")
                    ForEach(PlayerChoice.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } footer: { Text("АниксПлеер — отдельное Android-приложение; в клиенте iOS он не используется.") }
            Section("Перемотка опенинга") {
                Stepper("\(preferences.rewindSeconds) сек.", value: Binding(get: { min(600, max(0, preferences.rewindSeconds)) },
                                                                         set: { preferences.setRewindSeconds($0) }), in: 0...600, step: 5)
                Text("Рекомендуемое время: 85 секунд (1 мин. 25 сек.).").font(.ax(.caption)).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Воспроизведение").navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
struct DeviceAppearanceSettingsView: View {
    @AppStorage(DeviceAppearancePreferenceKey.colorScheme) private var colorScheme = AppColorSchemePreference.system.rawValue
    @AppStorage(ProfileWatchTimeFormat.storageKey) private var watchTime = ProfileWatchTimeFormat.daysAndHours.rawValue
    @AppStorage(DeviceAppearancePreferenceKey.defaultBookmarks) private var bookmarks = BookmarksView.BookmarkTab.favorites.storageKey
    @State private var home = HomePreferences()
    @AppStorage(DeviceAppearancePreferenceKey.visualTheme) private var visualTheme = AppVisualTheme.original.rawValue
    @AppStorage(DeviceAppearancePreferenceKey.accent) private var accent = AppAccentChoice.anixart.rawValue
    var body: some View {
        Form {
            Section {
                Picker("Тема", selection: $visualTheme) {
                    ForEach(AppVisualTheme.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Акцентный цвет", selection: $accent) {
                    ForEach(AppAccentChoice.allCases) { value in
                        Label { Text(value.title) } icon: { Circle().fill(value.seed.color).frame(width: 12, height: 12) }
                            .tag(value.rawValue)
                    }
                }
            } footer: { Text(AppVisualTheme.stored(visualTheme).detail) }
            Picker("Тёмная тема", selection: $colorScheme) {
                ForEach(AppColorSchemePreference.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .disabled(AppVisualTheme.stored(visualTheme) == .oled)
            AppTypefacePickerRow()
            Picker("Время просмотра в профиле", selection: $watchTime) {
                ForEach(ProfileWatchTimeFormat.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Section("Вкладки по умолчанию") {
                Picker("Главная", selection: Binding(get: { home.defaultTab.storageKey }, set: { key in
                    if let tab = HomeTab(storageKey: key) { home.setDefaultTab(tab) }
                })) { ForEach(HomeTab.allCases) { Text($0.title).tag($0.storageKey) } }
                Picker("Закладки", selection: $bookmarks) {
                    ForEach(BookmarksView.BookmarkTab.allCases, id: \.self) { Text($0.title).tag($0.storageKey) }
                }
            }
        }
        .background(Theme.background)
        .navigationTitle("Внешний вид").navigationBarTitleDisplayMode(.inline)
    }
}

enum ImageCacheSettings {
    static let storageKey = "data.imageCacheLimitMB"
    static let defaultLimitMB = 512
    static func boundedLimit(_ value: Int) -> Int { min(2048, max(128, value)) }
}

@MainActor
struct DeviceDataSettingsView: View {
    @State private var limit = Double(ImageCacheSettings.boundedLimit(UserDefaults.standard.object(forKey: ImageCacheSettings.storageKey) as? Int ?? ImageCacheSettings.defaultLimitMB))
    @State private var usedBytes = 0
    @State private var confirmsClear = false
    @State private var isBusy = false
    var body: some View {
        Form {
            Section("Кэш изображений") {
                LabeledContent("Использовано", value: ByteCountFormatter.string(fromByteCount: Int64(usedBytes), countStyle: .file))
                LabeledContent("Лимит", value: "\(Int(limit)) МБ")
                Slider(value: $limit, in: 128...2048, step: 128)
                Button("Сохранить лимит") { Task {
                    await ImageLoader.shared.setCacheLimit(mebibytes: Int(limit))
                    usedBytes = await ImageLoader.shared.cacheUsage()
                } }
                Button("Очистить кэш изображений", role: .destructive) { confirmsClear = true }
            }
        }
        .navigationTitle("Управление данными").navigationBarTitleDisplayMode(.inline)
        .disabled(isBusy)
        .task { usedBytes = await ImageLoader.shared.cacheUsage() }
        .confirmationDialog("Очистить кэш изображений?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Очистить", role: .destructive) { Task {
                isBusy = true
                await ImageLoader.shared.clearCache()
                usedBytes = await ImageLoader.shared.cacheUsage()
                isBusy = false
            } }
            Button("Отмена", role: .cancel) { }
        } message: { Text("Изображения будут загружены заново. Данные аккаунта и списки просмотра не удаляются.") }
    }
}

struct DeviceAdditionalSettingsView: View {
    @AppStorage(DeviceAppearancePreferenceKey.continueWatching) private var continueWatching = true
    @AppStorage(DeviceAppearancePreferenceKey.resourceSaving) private var resourceSaving = false
    var body: some View {
        Form {
            Section { Toggle("Продолжить просмотр", isOn: $continueWatching) } footer: {
                Text("Плашка с последней просмотренной серией на Главной и в Закладках.")
            }
            Section { Toggle("Экономия ресурсов", isOn: $resourceSaving) } footer: {
                Text("Приостанавливает анимацию витрины и GIF-аватаров. Системная настройка уменьшения движения также учитывается.")
            }
        }
        .navigationTitle("Дополнительно").navigationBarTitleDisplayMode(.inline)
    }
}

/// Вибро-отклик, подстраивающийся под происходящее: лайки и закладки отдаются
/// коротким «пружинистым» паттерном, пропуск опенинга и смена серии -- своим,
/// а системные события (ошибки, подтверждение необратимых действий) -- резким.
/// Сила и то, какие группы событий откликаются, настраиваются здесь.
@MainActor
struct DeviceHapticsSettingsView: View {
    @AppStorage(AppHapticsPreferenceKey.enabled) private var enabled = true
    @AppStorage(AppHapticsPreferenceKey.intensity) private var intensity = AppHapticIntensity.normal.rawValue
    @AppStorage(AppHapticCategory.interface.storageKey) private var interfaceEnabled = true
    @AppStorage(AppHapticCategory.social.storageKey) private var socialEnabled = true
    @AppStorage(AppHapticCategory.player.storageKey) private var playerEnabled = true
    @AppStorage(AppHapticCategory.system.storageKey) private var systemEnabled = true
    @AppStorage(AppHapticsPreferenceKey.contentReactive) private var contentReactive = false
    @AppStorage(AppHapticsPreferenceKey.contentSensitivity) private var contentSensitivity = AppHapticContentSensitivity.normal.rawValue

    private func isOn(_ category: AppHapticCategory) -> Binding<Bool> {
        switch category {
        case .interface: return $interfaceEnabled
        case .social: return $socialEnabled
        case .player: return $playerEnabled
        case .system: return $systemEnabled
        }
    }

    var body: some View {
        Form {
            Section { Toggle("Вибро-отклик", isOn: $enabled) } footer: {
                Text("Короткая вибрация на лайки, закладки, события плеера и системные уведомления. Подстраивается под то, что происходит -- у разных событий разный характер отклика.")
            }
            Section("Сила") {
                Picker("Сила отклика", selection: $intensity) {
                    ForEach(AppHapticIntensity.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .disabled(!enabled)
                Button("Проверить") { AppHaptics.shared.play(.likeOn) }
                    .disabled(!enabled)
            }
            Section("События") {
                ForEach(AppHapticCategory.allCases) { category in
                    Toggle(isOn: isOn(category)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.title)
                            Text(category.detail).font(.ax(.caption)).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!enabled)
                }
            }
            Section {
                Toggle("Реакция на звук в аниме", isOn: $contentReactive)
                    .disabled(!enabled || !playerEnabled)
                Picker("Чувствительность", selection: $contentSensitivity) {
                    ForEach(AppHapticContentSensitivity.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .disabled(!enabled || !playerEnabled || !contentReactive)
            } footer: {
                Text("Экспериментально: вибрация на резкий всплеск громкости в звуке самой серии -- выстрел, взрыв, удар. Это не распознавание сцен, а реакция на громкость, поэтому может сработать и на громкую музыку. Действует только во встроенном плеере и применяется при открытии следующей серии или смене качества.")
            }
        }
        .navigationTitle("Вибро-отклик").navigationBarTitleDisplayMode(.inline)
    }
}
