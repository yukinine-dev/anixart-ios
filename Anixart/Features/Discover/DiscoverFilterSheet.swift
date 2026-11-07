import SwiftUI
import AnixartKit

/// The filter opened from Android's Overview tab.
///
/// This is intentionally separate from the full catalogue filter. Android exposes
/// only these five controls here: country, category, genres, bookmark exclusions and
/// voiceover types. Keeping the same scope is important because the Overview filter
/// is a quick filter, not the advanced catalogue form.
@MainActor
struct DiscoverFilterSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let onApply: (FilterRequest) -> Void
    let onReset: () -> Void

    @State private var draft: CatalogFilterDraft
    @State private var availableTypes: [EpisodeType] = []
    @State private var isLoadingTypes = false
    @State private var typesError: String?

    init(current: FilterRequest, onApply: @escaping (FilterRequest) -> Void, onReset: @escaping () -> Void) {
        self.onApply = onApply
        self.onReset = onReset
        _draft = State(initialValue: CatalogFilterDraft(current))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    countryField
                    categoryField
                    genresField
                    exclusionsField
                    voiceoverField

                    if let validation = draft.validationMessage {
                        Text(validation)
                            .font(.ax(.subheadline))
                            .foregroundStyle(.red)
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .task { await loadTypes() }
            .onChange(of: env.session.viewerKey) { _, _ in dismiss() }
        }
    }

    private var countryField: some View {
        SingleChoiceField(
            title: "Страна",
            options: FilterOptions.countries.map { FilterOption($0) },
            label: \.title,
            selection: Binding(
                get: { draft.request.country.map { FilterOption($0) } },
                set: { draft.request.country = $0?.value }
            )
        )
    }

    private var categoryField: some View {
        SingleChoiceField(
            title: "Категория",
            options: ReleaseCategory.allCases,
            label: \.title,
            selection: Binding(get: { draft.category }, set: { draft.category = $0 })
        )
    }

    private var genresField: some View {
        GroupedMultiChoiceField(
            title: "Жанры",
            footnote: draft.genreMode.hint,
            groups: FilterOptions.genreGroups.map { (title: $0.title, options: $0.genres) },
            selection: Binding(get: { draft.genres }, set: { draft.genres = $0 }),
            matchingMode: Binding(get: { draft.genreMode }, set: { draft.genreMode = $0 })
        )
    }

    private var exclusionsField: some View {
        MultiChoiceField(
            title: "Исключить закладки",
            footnote: "Исключит из выдачи все релизы, содержащиеся в вышеуказанных списках закладок.",
            options: OverviewExcludedList.allCases,
            label: \.title,
            selection: Binding(
                get: {
                    (draft.request.profileListExclusions ?? []).compactMap(OverviewExcludedList.init(rawValue:))
                },
                set: {
                    draft.request.profileListExclusions = $0.isEmpty ? nil : $0.map(\.rawValue)
                }
            )
        )
    }

    private var typeOptions: [FilterOption<Int>] {
        let known = availableTypes.map { FilterOption($0.id, title: $0.displayName) }
        let ids = Set(known.map(\.value))
        return known + (draft.request.types ?? [])
            .filter { !ids.contains($0) }
            .map { FilterOption($0, title: "Вариант \($0)") }
    }

    private var voiceoverField: some View {
        VStack(alignment: .leading, spacing: 8) {
            MultiChoiceField(
                title: "Варианты озвучек",
                options: typeOptions,
                label: \.title,
                selection: Binding(
                    get: {
                        (draft.request.types ?? []).compactMap { id in
                            typeOptions.first { $0.value == id }
                        }
                    },
                    set: { draft.request.types = $0.isEmpty ? nil : $0.map(\.value) }
                ),
                showsSearch: true
            )
            .disabled(isLoadingTypes || typesError != nil)

            if isLoadingTypes {
                ProgressView()
                    .accessibilityLabel("Загрузка вариантов озвучки")
            }
            if let typesError {
                Text(typesError)
                    .font(.ax(.caption))
                    .foregroundStyle(.secondary)
                Button("Повторить") { Task { await loadTypes() } }
                    .font(.ax(.subheadline))
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                draft.reset()
                onReset()
            } label: {
                actionLabel("Сбросить", filled: false)
            }

            Button {
                onApply(draft.filter)
                dismiss()
            } label: {
                actionLabel("Применить", filled: true)
            }
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
            if !ProfileRequestFailure.isCancellation(error) {
                typesError = Paginator<Release>.message(for: error)
            }
        }
    }
}

/// Android includes Избранное (0) in this picker in addition to the five profile lists.
private enum OverviewExcludedList: Int, CaseIterable, Hashable, Identifiable {
    case favorites = 0
    case watching = 1
    case plan = 2
    case completed = 3
    case holdOn = 4
    case dropped = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .favorites: return "Избранное"
        case .watching: return "Смотрю"
        case .plan: return "В планах"
        case .completed: return "Просмотрено"
        case .holdOn: return "Отложено"
        case .dropped: return "Брошено"
        }
    }
}