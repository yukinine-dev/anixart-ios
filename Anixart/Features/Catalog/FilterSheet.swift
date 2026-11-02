import SwiftUI
import AnixartKit

/// `fragment_filter`: collapsed outlined choices, the same field order and paired
/// year/season and episode/status rows, with Reset/Apply always reachable below.
@MainActor
struct FilterSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let onApply: (FilterRequest) -> Void
    let onReset: () -> Void

    @State private var draft: CatalogFilterDraft
    @State private var availableTypes: [EpisodeType] = []
    @State private var isLoadingTypes = false
    @State private var typesError: String?
    @State private var isShowingYears = false

    private let ageRatingLabels = ["0+", "6+", "12+", "16+", "18+"]

    init(current: FilterRequest, onApply: @escaping (FilterRequest) -> Void, onReset: @escaping () -> Void) {
        self.onApply = onApply
        self.onReset = onReset
        _draft = State(initialValue: CatalogFilterDraft(current))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    fields
                    if let validation = draft.validationMessage {
                        Text(validation).font(.ax(.subheadline)).foregroundStyle(.red)
                    }
                }
                .padding(16)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom) { actions }
            .navigationTitle("Фильтр")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
            .sheet(isPresented: $isShowingYears) {
                FilterYearRangeSheet(startYear: draft.request.startYear, endYear: draft.request.endYear) { start, end in
                    draft.request.startYear = start
                    draft.request.endYear = end
                }
            }
            .task { await loadTypes() }
            .onChange(of: env.session.viewerKey) { _, _ in dismiss() }
        }
    }

    @ViewBuilder
    private var fields: some View {
        basicFields
        releaseFields
    }

    @ViewBuilder
    private var basicFields: some View {
        SingleChoiceField(
            title: "Страна", options: FilterOptions.countries.map { FilterOption($0) }, label: \.title,
            selection: Binding(get: { draft.request.country.map { FilterOption($0) } }, set: { draft.request.country = $0?.value })
        )
        SingleChoiceField(title: "Категория", options: ReleaseCategory.allCases, label: \.title,
                          selection: Binding(get: { draft.category }, set: { draft.category = $0 }))

        GroupedMultiChoiceField(
            title: "Жанры", footnote: draft.genreMode.hint,
            groups: FilterOptions.genreGroups.map { (title: $0.title, options: $0.genres) },
            selection: Binding(get: { draft.genres }, set: { draft.genres = $0 }),
            matchingMode: Binding(get: { draft.genreMode }, set: { draft.genreMode = $0 })
        )
        MultiChoiceField(
            title: "Исключить закладки",
            footnote: "Исключит из выдачи все релизы, содержащиеся в вышеуказанных списках закладок.",
            options: ProfileListStatus.allCases, label: \.title,
            selection: Binding(get: { draft.excludedLists }, set: { draft.excludedLists = $0 })
        )
        voiceOverField
    }

    @ViewBuilder
    private var releaseFields: some View {
        SearchableChoiceField(
            title: "Студия", options: FilterOptions.studios.map { FilterOption($0) }, label: \.title,
            selection: Binding(get: { draft.request.studio.map { FilterOption($0) } }, set: { draft.request.studio = $0?.value })
        )
        SingleChoiceField(title: "Первоисточник", options: SourceMaterial.allCases, label: \.title,
                          selection: Binding(get: { draft.source }, set: { draft.source = $0 }))

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) { yearsField; seasonField }
            VStack(alignment: .leading, spacing: 24) { yearsField; seasonField }
        }
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) { episodesField; statusField }
            VStack(alignment: .leading, spacing: 24) { episodesField; statusField }
        }
        SingleChoiceField(title: "Длительность эпизода", options: EpisodeDurationPreset.allCases, label: \.title,
                          selection: Binding(get: { draft.episodeDuration }, set: { draft.episodeDuration = $0 }))
        MultiChoiceField(
            title: "Возрастное ограничение",
            options: ageRatingLabels.enumerated().map { FilterOption($0.offset, title: $0.element) }, label: \.title,
            selection: Binding(get: { draft.ageRatings.map { ageOption($0) } }, set: { draft.ageRatings = $0.map(\.value) })
        )
        SingleChoiceField(
            title: "Сортировка", footnote: draft.sort.title, options: CatalogSort.displayOrder, label: \.shortTitle,
            selection: Binding(get: { Optional(draft.sort) }, set: { draft.sort = $0 ?? .dateUpdateDescending }),
            allowsEmpty: false
        )
    }

    private var yearsField: some View {
        FilterFieldBox(title: "Года") {
            Button { isShowingYears = true } label: { FilterValueLabel(value: draft.yearsSummary) }
                .buttonStyle(.plain)
        }
    }

    private var seasonField: some View {
        SingleChoiceField(title: "Сезон", options: ReleaseSeason.allCases, label: { $0.title.capitalized },
                          selection: Binding(get: { draft.season }, set: { draft.season = $0 }))
    }

    private var episodesField: some View {
        SingleChoiceField(title: "Эпизодов", options: EpisodeCountPreset.allCases, label: \.title,
                          selection: Binding(get: { draft.episodes }, set: { draft.episodes = $0 }))
    }

    private var statusField: some View {
        SingleChoiceField(title: "Статус", options: AiringStatus.allCases, label: \.title,
                          selection: Binding(get: { draft.status }, set: { draft.status = $0 }))
    }

    private var typeOptions: [FilterOption<Int>] {
        let known = availableTypes.map { FilterOption($0.id, title: $0.displayName) }
        let ids = Set(known.map(\.value))
        return known + draft.typeIDs.filter { !ids.contains($0) }.map { FilterOption($0, title: "Вариант \($0)") }
    }

    private var voiceOverField: some View {
        VStack(alignment: .leading, spacing: 8) {
            MultiChoiceField(
                title: "Варианты озвучек", options: typeOptions, label: \.title,
                selection: Binding(
                    get: { draft.typeIDs.compactMap { id in typeOptions.first { $0.value == id } } },
                    set: { draft.typeIDs = $0.map(\.value) }
                ), showsSearch: true
            )
            .disabled(isLoadingTypes || typesError != nil)
            if isLoadingTypes { ProgressView().accessibilityLabel("Загрузка вариантов озвучки") }
            if let typesError {
                Text(typesError).font(.ax(.caption)).foregroundStyle(.secondary)
                Button("Повторить") { Task { await loadTypes() } }.font(.ax(.subheadline))
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                draft.reset()
                onReset()
                // Stay in the form so the cleared values are visible and can be
                // adjusted before Apply, as in the original filter.
            } label: { actionLabel("Сбросить", filled: false) }
            Button {
                onApply(draft.filter)
                dismiss()
            } label: { actionLabel("Применить", filled: true) }
                .disabled(draft.validationMessage != nil)
                .opacity(draft.validationMessage == nil ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func actionLabel(_ title: String, filled: Bool) -> some View {
        Text(title)
            .font(.ax(.body, .medium))
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 8)
            .foregroundStyle(filled ? Color(.systemBackground) : Color.primary)
            .background(filled ? Color.primary : Color.clear, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: filled ? 0 : 1) }
            .contentShape(Capsule())
    }

    private func ageOption(_ index: Int) -> FilterOption<Int> {
        FilterOption(index, title: ageRatingLabels.indices.contains(index) ? ageRatingLabels[index] : String(index))
    }

    private func loadTypes() async {
        guard !isLoadingTypes else { return }
        isLoadingTypes = true
        typesError = nil
        defer { isLoadingTypes = false }
        let viewer = env.session.viewerKey
        do {
            let response = try await env.session.sendViewerRequest(ReleaseEndpoints.allTypes(), for: viewer)
            guard let types = response.types else {
                throw AnixartError.decoding(message: "Сервер не вернул варианты озвучки", path: "type/all")
            }
            var seen = Set<Int>()
            availableTypes = types.filter { seen.insert($0.id).inserted }
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { typesError = Paginator<Release>.message(for: error) }
        }
    }
}

/// The year range is one collapsed field on the main form, with an explicit
/// Apply/Cancel boundary for its two endpoints.
@MainActor
private struct FilterYearRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var startYear: Int?
    @State private var endYear: Int?
    let onApply: (Int?, Int?) -> Void

    init(startYear: Int?, endYear: Int?, onApply: @escaping (Int?, Int?) -> Void) {
        _startYear = State(initialValue: startYear)
        _endYear = State(initialValue: endYear)
        self.onApply = onApply
    }

    private var validationMessage: String? { FilterRequest(startYear: startYear, endYear: endYear).validationMessage }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    YearRangeField(startYear: $startYear, endYear: $endYear)
                    if let validationMessage { Text(validationMessage).font(.ax(.subheadline)).foregroundStyle(.red) }
                }.padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Фильтр по годам")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Применить") { onApply(startYear, endYear); dismiss() }
                        .disabled(validationMessage != nil)
                }
                ToolbarItem(placement: .bottomBar) { Button("Сбросить") { startYear = nil; endYear = nil } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
