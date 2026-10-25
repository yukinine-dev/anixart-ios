import SwiftUI
import AnixartKit

/// "Настройки вкладки" -- the whole filter behind Моя вкладка.
///
/// Field list mirrors the Android screen: country, category, genres with a match mode,
/// bookmark exclusions, voice-over, studio, source material, years, season, episode
/// count, status, episode length, age rating and sort. Options come from the APK's
/// `arrays.xml`; voice-overs come from the server so they stay in step with it.
@MainActor
struct CustomTabSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let current: CustomTabFilter
    let onApply: (CustomTabFilter) -> Void
    let onReset: () -> Void

    @State private var draft = CustomTabFilter()
    @State private var availableTypes: [EpisodeType] = []
    @State private var genreInput = ""

    private let ageRatingLabels = ["0+", "6+", "12+", "16+", "18+"]
    private let countries = ["Япония", "Китай", "Корея", "США"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Выберите с помощью фильтров то, что хотите видеть на своей вкладке. "
                         + "Изменения будут доступны только на этом устройстве.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    optionalPicker("Страна", selection: $draft.country, options: countries)

                    Picker("Категория", selection: $draft.category) {
                        Text("Неважно").tag(ReleaseCategory?.none)
                        ForEach(ReleaseCategory.allCases) { value in
                            Text(value.title).tag(ReleaseCategory?.some(value))
                        }
                    }

                    Picker("Статус", selection: $draft.status) {
                        Text("Неважно").tag(AiringStatus?.none)
                        ForEach(AiringStatus.allCases) { value in
                            Text(value.title).tag(AiringStatus?.some(value))
                        }
                    }
                }

                genresSection
                exclusionsSection

                if !availableTypes.isEmpty {
                    Section("Варианты озвучек") {
                        ForEach(availableTypes) { type in
                            Toggle(type.displayName, isOn: typeBinding(type.id))
                        }
                    }
                }

                Section {
                    TextField("Студия", text: $draft.studio)

                    Picker("Первоисточник", selection: $draft.source) {
                        Text("Неважно").tag(SourceMaterial?.none)
                        ForEach(SourceMaterial.allCases) { value in
                            Text(value.title).tag(SourceMaterial?.some(value))
                        }
                    }
                }

                Section {
                    yearField("Год от", value: $draft.startYear)
                    yearField("Год до", value: $draft.endYear)

                    Picker("Сезон", selection: $draft.season) {
                        Text("Неважно").tag(ReleaseSeason?.none)
                        ForEach(ReleaseSeason.allCases) { value in
                            Text(value.title.capitalized).tag(ReleaseSeason?.some(value))
                        }
                    }
                }

                Section {
                    Picker("Эпизодов", selection: $draft.episodes) {
                        Text("Неважно").tag(EpisodeCountPreset?.none)
                        ForEach(EpisodeCountPreset.allCases) { value in
                            Text(value.title).tag(EpisodeCountPreset?.some(value))
                        }
                    }

                    Picker("Длительность эпизода", selection: $draft.episodeDuration) {
                        Text("Неважно").tag(EpisodeDurationPreset?.none)
                        ForEach(EpisodeDurationPreset.allCases) { value in
                            Text(value.title).tag(EpisodeDurationPreset?.some(value))
                        }
                    }
                }

                Section("Возрастное ограничение") {
                    ForEach(Array(ageRatingLabels.enumerated()), id: \.offset) { index, label in
                        Toggle(label, isOn: ageRatingBinding(index))
                    }
                }

                Section {
                    Picker("Сортировка", selection: $draft.sort) {
                        ForEach(CatalogSort.displayOrder) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } header: {
                    Text("Сортировка")
                } footer: {
                    Text(draft.sort.title)
                }
            }
            .navigationTitle("Настройки вкладки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Сбросить") {
                        draft = CustomTabFilter()
                        onReset()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Применить") {
                        onApply(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .task {
                draft = current
                if availableTypes.isEmpty,
                   let response = try? await env.client.send(ReleaseEndpoints.allTypes()) {
                    availableTypes = response.types ?? []
                }
            }
        }
    }

    // MARK: - Sections

    private var genresSection: some View {
        Section {
            ForEach(draft.genres, id: \.self) { genre in
                HStack {
                    Text(genre)
                    Spacer()
                    Button {
                        draft.genres.removeAll { $0 == genre }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                TextField("Добавить жанр", text: $genreInput)
                Button("Добавить") { addGenre() }
                    .disabled(genreInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Picker("Режим", selection: $draft.genresMode) {
                ForEach(GenresMode.allCases, id: \.rawValue) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        } header: {
            Text("Жанры")
        } footer: {
            Text("Покажем релизы хотя бы с одним выбранным жанром.")
        }
    }

    private var exclusionsSection: some View {
        Section {
            ForEach(ProfileListStatus.allCases) { status in
                Toggle("Скрыть «\(status.title)»", isOn: exclusionBinding(status))
            }
        } header: {
            Text("Исключить закладки")
        } footer: {
            Text("Исключит из выдачи все релизы, содержащиеся в вышеуказанных списках закладок.")
        }
    }

    // MARK: - Fields

    private func optionalPicker(
        _ title: String,
        selection: Binding<String>,
        options: [String]
    ) -> some View {
        Picker(title, selection: selection) {
            Text("Неважно").tag("")
            ForEach(options, id: \.self) { option in
                Text(option).tag(option)
            }
        }
    }

    private func yearField(_ title: String, value: Binding<Int?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: Binding(
                get: { value.wrappedValue.map { String($0) } ?? "" },
                set: { value.wrappedValue = Int($0.filter(\.isNumber)) }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
        }
    }

    private func addGenre() {
        let genre = genreInput.trimmingCharacters(in: .whitespaces)
        guard !genre.isEmpty, !draft.genres.contains(genre) else {
            genreInput = ""
            return
        }
        draft.genres.append(genre)
        genreInput = ""
    }

    private func ageRatingBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { draft.ageRatings.contains(index) },
            set: { isOn in
                if isOn {
                    draft.ageRatings.append(index)
                    draft.ageRatings.sort()
                } else {
                    draft.ageRatings.removeAll { $0 == index }
                }
            }
        )
    }

    private func typeBinding(_ id: Int) -> Binding<Bool> {
        Binding(
            get: { draft.types.contains(id) },
            set: { isOn in
                if isOn { draft.types.append(id) } else { draft.types.removeAll { $0 == id } }
            }
        )
    }

    private func exclusionBinding(_ status: ProfileListStatus) -> Binding<Bool> {
        Binding(
            get: { draft.profileListExclusions.contains(status) },
            set: { isOn in
                if isOn {
                    draft.profileListExclusions.append(status)
                } else {
                    draft.profileListExclusions.removeAll { $0 == status }
                }
            }
        )
    }
}
