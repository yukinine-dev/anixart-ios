import SwiftUI
import AnixartKit

/// "Настройки вкладки" -- the filter behind Моя вкладка.
///
/// Laid out as the Android screen is: a column of labelled boxes, each collapsed to
/// its current value or «Неважно», with the options behind a tap rather than spread
/// inline, and Сбросить / Применить pinned at the bottom. Option lists come from the
/// APK's `arrays.xml` (`FilterOptions`), not from free text.
@MainActor
struct CustomTabSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let current: CustomTabFilter
    let onApply: (CustomTabFilter) -> Void
    let onReset: () -> Void

    @State private var draft = CustomTabFilter()
    @State private var availableTypes: [EpisodeType] = []

    private static let ageRatingOptions = ["0+", "6+", "12+", "16+", "18+"]
        .enumerated()
        .map { FilterOption($0.offset, title: $0.element) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hint
                    fields
                }
                .padding()
                .padding(.bottom, 8)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) { actions }
            .navigationTitle("Настройки вкладки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
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

    private var hint: some View {
        Text("Выберите с помощью фильтров то, что хотите видеть на своей вкладке. "
             + "Изменения будут доступны только на этом устройстве.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var fields: some View {
        SearchableChoiceField(
            title: "Страна",
            options: FilterOptions.countries.map { FilterOption($0) },
            label: \.title,
            selection: Binding(
                get: { draft.country.isEmpty ? nil : FilterOption(draft.country) },
                set: { draft.country = $0?.value ?? "" }
            )
        )

        SingleChoiceField(
            title: "Категория",
            options: ReleaseCategory.allCases,
            label: \.title,
            selection: $draft.category
        )

        GroupedMultiChoiceField(
            title: "Жанры",
            footnote: "Покажем релизы хотя бы с одним выбранным жанром.",
            groups: FilterOptions.genreGroups.map { (title: $0.title, options: $0.genres) },
            selection: $draft.genres
        )

        if !draft.genres.isEmpty {
            SingleChoiceField(
                title: "Режим жанров",
                options: GenresMode.allCases.map { FilterOption($0.rawValue, title: $0.title) },
                label: \.title,
                selection: Binding(
                    get: { FilterOption(draft.genresMode.rawValue, title: draft.genresMode.title) },
                    set: { draft.genresMode = $0.flatMap { GenresMode(rawValue: $0.value) } ?? .all }
                )
            )
        }

        MultiChoiceField(
            title: "Исключить закладки",
            footnote: "Исключит из выдачи все релизы, содержащиеся в вышеуказанных списках закладок.",
            options: ProfileListStatus.allCases,
            label: \.title,
            selection: $draft.profileListExclusions
        )

        if !availableTypes.isEmpty {
            MultiChoiceField(
                title: "Варианты озвучек",
                options: availableTypes.map { FilterOption($0.id, title: $0.displayName) },
                label: \.title,
                selection: Binding(
                    get: {
                        draft.types.compactMap { id in
                            availableTypes.first { $0.id == id }
                                .map { FilterOption($0.id, title: $0.displayName) }
                        }
                    },
                    set: { draft.types = $0.map(\.value) }
                )
            )
        }

        SearchableChoiceField(
            title: "Студия",
            options: FilterOptions.studios.map { FilterOption($0) },
            label: \.title,
            selection: Binding(
                get: { draft.studio.isEmpty ? nil : FilterOption(draft.studio) },
                set: { draft.studio = $0?.value ?? "" }
            )
        )

        SingleChoiceField(
            title: "Первоисточник",
            options: SourceMaterial.allCases,
            label: \.title,
            selection: $draft.source
        )

        YearRangeField(startYear: $draft.startYear, endYear: $draft.endYear)

        SingleChoiceField(
            title: "Сезон",
            options: ReleaseSeason.allCases,
            label: { $0.title.capitalizedFirst },
            selection: $draft.season
        )

        SingleChoiceField(
            title: "Эпизодов",
            options: EpisodeCountPreset.allCases,
            label: \.title,
            selection: $draft.episodes
        )

        SingleChoiceField(
            title: "Статус",
            options: AiringStatus.allCases,
            label: \.title,
            selection: $draft.status
        )

        SingleChoiceField(
            title: "Длительность эпизода",
            options: EpisodeDurationPreset.allCases,
            label: \.title,
            selection: $draft.episodeDuration
        )

        MultiChoiceField(
            title: "Возрастное ограничение",
            options: Self.ageRatingOptions,
            label: \.title,
            selection: Binding(
                get: { draft.ageRatings.compactMap { value in Self.ageRatingOptions.first { $0.value == value } } },
                set: { draft.ageRatings = $0.map(\.value).sorted() }
            )
        )

        SingleChoiceField(
            title: "Сортировка",
            footnote: draft.sort.title,
            options: CatalogSort.displayOrder,
            label: \.shortTitle,
            selection: Binding(
                get: { draft.sort },
                set: { draft.sort = $0 ?? .dateUpdateDescending }
            )
        )
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button("Сбросить") {
                draft = CustomTabFilter()
                onReset()
                dismiss()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)

            Button("Применить") {
                onApply(draft)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
