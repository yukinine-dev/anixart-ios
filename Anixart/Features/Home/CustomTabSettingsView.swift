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
    @Environment(\.dismiss) private var dismiss

    let current: CustomTabFilter
    let onApply: (CustomTabFilter) -> Void
    let onReset: () -> Void

    @State private var draft = CustomTabFilter()

    init(current: CustomTabFilter, onApply: @escaping (CustomTabFilter) -> Void, onReset: @escaping () -> Void) {
        self.current = current
        self.onApply = onApply
        self.onReset = onReset
        _draft = State(initialValue: current)
    }

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
        }
    }

    private var hint: some View {
        Text("Выберите с помощью фильтров то, что хотите видеть на своей вкладке. "
             + "Изменения будут доступны только на этом устройстве.")
            .font(.ax(.footnote))
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

        MultiChoiceField(
            title: "Исключить закладки",
            footnote: "Исключит из выдачи все релизы, содержащиеся в вышеуказанных списках закладок.",
            options: ProfileListStatus.allCases,
            label: \.title,
            selection: $draft.profileListExclusions
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
