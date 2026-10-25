import SwiftUI
import AnixartKit

/// Catalogue filter. Mirrors the fields `FilterRequest` accepts in the APK; the
/// genre and voice-over lists come from the server so they stay in step with it.
@MainActor
struct FilterSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let current: FilterRequest
    let onApply: (FilterRequest) -> Void
    let onReset: () -> Void

    @State private var draft = FilterRequest()
    @State private var availableTypes: [EpisodeType] = []
    @State private var genreInput = ""

    private let ageRatingLabels = ["0+", "6+", "12+", "16+", "18+"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Сортировка") {
                    Picker("Порядок", selection: Binding(
                        get: { CatalogSort(rawValue: draft.sort ?? 0) ?? .dateUpdateDescending },
                        set: { draft.sort = $0.rawValue }
                    )) {
                        ForEach(CatalogSort.displayOrder) { option in
                            Text(option.shortTitle).tag(option)
                        }
                    }
                }

                Section("Сезон и год") {
                    Picker("Сезон", selection: Binding(
                        get: { draft.season.flatMap(ReleaseSeason.init(rawValue:)) },
                        set: { draft.season = $0?.rawValue }
                    )) {
                        Text("Любой").tag(ReleaseSeason?.none)
                        ForEach(ReleaseSeason.allCases) { season in
                            Text(season.title.capitalized).tag(ReleaseSeason?.some(season))
                        }
                    }

                    yearField("Год от", value: $draft.startYear)
                    yearField("Год до", value: $draft.endYear)
                }

                Section("Количество эпизодов") {
                    // The preset resolves into an explicit from/to range; its index is
                    // a UI position and must not reach the request.
                    Picker("Эпизодов", selection: Binding(
                        get: {
                            EpisodeCountPreset.allCases.first {
                                $0.range.from == draft.episodesFrom && $0.range.to == draft.episodesTo
                            }
                        },
                        set: { preset in
                            draft.episodesFrom = preset?.range.from
                            draft.episodesTo = preset?.range.to
                        }
                    )) {
                        Text("Любое").tag(EpisodeCountPreset?.none)
                        ForEach(EpisodeCountPreset.allCases) { preset in
                            Text(preset.title).tag(EpisodeCountPreset?.some(preset))
                        }
                    }

                    Picker("Длительность эпизода", selection: Binding(
                        get: {
                            EpisodeDurationPreset.allCases.first {
                                $0.range.from == draft.episodeDurationFrom
                                    && $0.range.to == draft.episodeDurationTo
                            }
                        },
                        set: { preset in
                            draft.episodeDurationFrom = preset?.range.from
                            draft.episodeDurationTo = preset?.range.to
                        }
                    )) {
                        Text("Любая").tag(EpisodeDurationPreset?.none)
                        ForEach(EpisodeDurationPreset.allCases) { preset in
                            Text(preset.title).tag(EpisodeDurationPreset?.some(preset))
                        }
                    }
                }

                Section("Категория и статус") {
                    Picker("Категория", selection: Binding(
                        get: { draft.categoryId.flatMap(ReleaseCategory.init(rawValue:)) },
                        set: { draft.categoryId = $0?.rawValue }
                    )) {
                        Text("Неважно").tag(ReleaseCategory?.none)
                        ForEach(ReleaseCategory.allCases) { value in
                            Text(value.title).tag(ReleaseCategory?.some(value))
                        }
                    }

                    Picker("Статус", selection: Binding(
                        get: { draft.statusId.flatMap(AiringStatus.init(rawValue:)) },
                        set: { draft.statusId = $0?.rawValue }
                    )) {
                        Text("Неважно").tag(AiringStatus?.none)
                        ForEach(AiringStatus.allCases) { value in
                            Text(value.title).tag(AiringStatus?.some(value))
                        }
                    }

                    Picker("Первоисточник", selection: Binding(
                        get: { draft.source.flatMap(SourceMaterial.init(rawValue:)) },
                        set: { draft.source = $0?.rawValue }
                    )) {
                        Text("Неважно").tag(SourceMaterial?.none)
                        ForEach(SourceMaterial.allCases) { value in
                            Text(value.title).tag(SourceMaterial?.some(value))
                        }
                    }
                }

                Section("Возрастной рейтинг") {
                    ForEach(Array(ageRatingLabels.enumerated()), id: \.offset) { index, label in
                        Toggle(label, isOn: binding(forAgeRating: index))
                    }
                }

                Section {
                    ForEach(draft.genres ?? [], id: \.self) { genre in
                        HStack {
                            Text(genre)
                            Spacer()
                            Button {
                                draft.genres?.removeAll { $0 == genre }
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
                    Picker("Режим", selection: Binding(
                        get: { draft.genresMode.flatMap(GenresMode.init(rawValue:)) ?? .all },
                        set: {
                            draft.genresMode = $0.rawValue
                            draft.isGenresExcludeModeEnabled = $0 == .exclude ? true : nil
                        }
                    )) {
                        ForEach(GenresMode.allCases, id: \.rawValue) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                } header: {
                    Text("Жанры")
                } footer: {
                    Text("Жанр указывается так, как он назван в каталоге, например «Драма».")
                }

                if !availableTypes.isEmpty {
                    Section("Озвучка") {
                        ForEach(availableTypes) { type in
                            Toggle(type.displayName, isOn: binding(forType: type.id))
                        }
                    }
                }

                Section {
                    ForEach(ProfileListStatus.allCases) { status in
                        Toggle("Скрыть «\(status.title)»", isOn: binding(forExclusion: status))
                    }
                } header: {
                    Text("Мои списки")
                } footer: {
                    Text("Исключает из каталога релизы, которые уже лежат в выбранных списках.")
                }

                Section("Прочее") {
                    TextField("Студия", text: optionalText($draft.studio))
                    TextField("Страна", text: optionalText($draft.country))
                }
            }
            .navigationTitle("Фильтры")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Сбросить") {
                        draft = FilterRequest()
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

    private func optionalText(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }

    private func addGenre() {
        let genre = genreInput.trimmingCharacters(in: .whitespaces)
        guard !genre.isEmpty else { return }
        var genres = draft.genres ?? []
        if !genres.contains(genre) { genres.append(genre) }
        draft.genres = genres
        genreInput = ""
    }

    private func binding(forAgeRating index: Int) -> Binding<Bool> {
        Binding(
            get: { draft.ageRatings?.contains(index) ?? false },
            set: { isOn in
                var values = draft.ageRatings ?? []
                if isOn { values.append(index) } else { values.removeAll { $0 == index } }
                draft.ageRatings = values.isEmpty ? nil : values.sorted()
            }
        )
    }

    private func binding(forType id: Int) -> Binding<Bool> {
        Binding(
            get: { draft.types?.contains(id) ?? false },
            set: { isOn in
                var values = draft.types ?? []
                if isOn { values.append(id) } else { values.removeAll { $0 == id } }
                draft.types = values.isEmpty ? nil : values
            }
        )
    }

    private func binding(forExclusion status: ProfileListStatus) -> Binding<Bool> {
        Binding(
            get: { draft.profileListExclusions?.contains(status.rawValue) ?? false },
            set: { isOn in
                var values = draft.profileListExclusions ?? []
                if isOn { values.append(status.rawValue) } else { values.removeAll { $0 == status.rawValue } }
                draft.profileListExclusions = values.isEmpty ? nil : values
            }
        )
    }
}
