import SwiftUI
import AnixartKit

/// Catalogue filter. Mirrors the fields `FilterRequest` accepts in the APK; the
/// genre/country/studio options come from the APK, voice-over types from the API.
@MainActor
struct FilterSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let current: FilterRequest
    let onApply: (FilterRequest) -> Void
    let onReset: () -> Void

    @State private var draft = FilterRequest()
    @State private var availableTypes: [EpisodeType] = []
    @State private var isLoadingTypes = false
    @State private var typesError: String?

    private let ageRatingLabels = ["0+", "6+", "12+", "16+", "18+"]

    init(current: FilterRequest, onApply: @escaping (FilterRequest) -> Void, onReset: @escaping () -> Void) {
        self.current = current
        self.onApply = onApply
        self.onReset = onReset
        _draft = State(initialValue: current.normalized)
    }

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
                    GroupedMultiChoiceField(
                        title: "Жанры",
                        groups: FilterOptions.genreGroups.map { (title: $0.title, options: $0.genres) },
                        selection: Binding(get: { draft.genres ?? [] }, set: {
                            draft.genres = $0.isEmpty ? nil : $0
                            if !$0.isEmpty, draft.genresMode == nil { draft.genresMode = GenresMode.any.rawValue }
                        })
                    )
                    Picker("Режим", selection: Binding(
                        get: { draft.genresMode.flatMap(GenresMode.init(rawValue:)) ?? .any },
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
                    Text((draft.genresMode.flatMap(GenresMode.init(rawValue:)) ?? .any).title)
                }

                if !availableTypes.isEmpty {
                    Section("Озвучка") {
                        ForEach(availableTypes) { type in
                            Toggle(type.displayName, isOn: binding(forType: type.id))
                        }
                    }
                } else if isLoadingTypes {
                    Section("Озвучка") { ProgressView() }
                } else if let typesError {
                    Section("Озвучка") {
                        Text(typesError).font(.ax(.subheadline)).foregroundStyle(.secondary)
                        Button("Повторить") { Task { await loadTypes() } }
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
                    SearchableChoiceField(
                        title: "Студия", options: FilterOptions.studios.map { FilterOption($0) }, label: \.title,
                        selection: Binding(get: { draft.studio.map { FilterOption($0) } }, set: { draft.studio = $0?.value })
                    )
                    SearchableChoiceField(
                        title: "Страна", options: FilterOptions.countries.map { FilterOption($0) }, label: \.title,
                        selection: Binding(get: { draft.country.map { FilterOption($0) } }, set: { draft.country = $0?.value })
                    )
                }
                if let validation = draft.validationMessage {
                    Section { Text(validation).font(.ax(.subheadline)).foregroundStyle(.red) }
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
                        onApply(draft.normalized)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.validationMessage != nil)
                }
            }
            .task { if availableTypes.isEmpty { await loadTypes() } }
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

    private func loadTypes() async {
        guard !isLoadingTypes else { return }
        isLoadingTypes = true
        typesError = nil
        defer { isLoadingTypes = false }
        let viewer = env.session.viewerKey
        do {
            let response = try await env.session.sendViewerRequest(ReleaseEndpoints.allTypes(), for: viewer)
            availableTypes = response.types ?? []
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { typesError = Paginator<Release>.message(for: error) }
        }
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
