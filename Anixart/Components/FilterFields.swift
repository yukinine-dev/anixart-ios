import SwiftUI

/// The filter controls the Android "Настройки вкладки" screen uses: a labelled box
/// showing the current value, or «Неважно» when nothing is chosen, which opens the
/// options rather than listing them inline.
///
/// That collapsing is the point. The screen has fourteen fields, several of them
/// multi-select over dozens of options; laid out as inline toggles it becomes a
/// scroll with no shape to it, which is what this port had before.
@MainActor
struct FilterFieldBox<Content: View>: View {
    let title: String
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            content

            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The bordered box itself: value on the left, chevron on the right.
@MainActor
struct FilterValueLabel: View {
    let value: String?
    var placeholder = "Неважно"

    var body: some View {
        HStack {
            Text(value ?? placeholder)
                .foregroundStyle(value == nil ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

/// Wraps a plain value so the choice fields can key on it. Genres, countries, studios
/// and age ratings are strings and ints in the API, none of which are `Identifiable`.
struct FilterOption<Value: Hashable>: Hashable, Identifiable {
    let value: Value
    let title: String

    var id: Value { value }

    init(_ value: Value, title: String? = nil) {
        self.value = value
        self.title = title ?? String(describing: value)
    }
}

/// One-of field. A menu keeps a short option list in place rather than pushing a screen.
@MainActor
struct SingleChoiceField<Option: Hashable & Identifiable>: View {
    let title: String
    var footnote: String?
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option?

    var body: some View {
        FilterFieldBox(title: title, footnote: footnote) {
            Menu {
                Picker(title, selection: $selection) {
                    Text("Неважно").tag(Option?.none)
                    ForEach(options) { option in
                        Text(label(option)).tag(Option?.some(option))
                    }
                }
            } label: {
                FilterValueLabel(value: selection.map(label))
            }
            .buttonStyle(.plain)
        }
    }
}

/// One-of field over a long list -- studios run to 173 entries, which is a scroll, not
/// a menu -- so this pushes a searchable screen instead.
@MainActor
struct SearchableChoiceField<Option: Hashable & Identifiable>: View {
    let title: String
    var footnote: String?
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option?

    var body: some View {
        FilterFieldBox(title: title, footnote: footnote) {
            NavigationLink {
                SearchableChoiceList(
                    title: title,
                    options: options,
                    label: label,
                    selection: $selection
                )
            } label: {
                FilterValueLabel(value: selection.map(label))
            }
            .buttonStyle(.plain)
        }
    }
}

@MainActor
struct SearchableChoiceList<Option: Hashable & Identifiable>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option?

    @State private var query = ""

    private var filtered: [Option] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return options }
        return options.filter { label($0).localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        List {
            Button {
                selection = nil
                dismiss()
            } label: {
                HStack {
                    Text("Неважно").foregroundStyle(.secondary)
                    Spacer()
                    if selection == nil {
                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(filtered) { option in
                Button {
                    selection = option
                    dismiss()
                } label: {
                    HStack {
                        Text(label(option)).foregroundStyle(.primary)
                        Spacer()
                        if selection == option {
                            Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Поиск")
    }
}

/// Many-of field. Pushes a checklist and collapses back to a summary: the first
/// choice, plus a count when there are more.
@MainActor
struct MultiChoiceField<Option: Hashable & Identifiable>: View {
    let title: String
    var footnote: String?
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: [Option]

    private var summary: String? {
        guard let first = selection.first else { return nil }
        return selection.count == 1
            ? label(first)
            : "\(label(first)) и ещё \(selection.count - 1)"
    }

    var body: some View {
        FilterFieldBox(title: title, footnote: footnote) {
            NavigationLink {
                MultiChoiceList(title: title, options: options, label: label, selection: $selection)
            } label: {
                FilterValueLabel(value: summary)
            }
            .buttonStyle(.plain)
        }
    }
}

@MainActor
struct MultiChoiceList<Option: Hashable & Identifiable>: View {
    let title: String
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: [Option]

    var body: some View {
        List {
            ForEach(options) { option in
                Button {
                    toggle(option)
                } label: {
                    HStack {
                        Text(label(option)).foregroundStyle(.primary)
                        Spacer()
                        if selection.contains(option) {
                            Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !selection.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сбросить") { selection.removeAll() }
                }
            }
        }
    }

    private func toggle(_ option: Option) {
        if let index = selection.firstIndex(of: option) {
            selection.remove(at: index)
        } else {
            selection.append(option)
        }
    }
}

/// Many-of field whose options come in named groups, as the genre picker does
/// (Жанры / Аудитория / Тематика, taken from the `@`-prefixed entries in the APK).
@MainActor
struct GroupedMultiChoiceField: View {
    let title: String
    var footnote: String?
    let groups: [(title: String, options: [String])]
    @Binding var selection: [String]

    private var summary: String? {
        guard let first = selection.first else { return nil }
        return selection.count == 1 ? first : "\(first) и ещё \(selection.count - 1)"
    }

    var body: some View {
        FilterFieldBox(title: title, footnote: footnote) {
            NavigationLink {
                GroupedMultiChoiceList(title: title, groups: groups, selection: $selection)
            } label: {
                FilterValueLabel(value: summary)
            }
            .buttonStyle(.plain)
        }
    }
}

@MainActor
struct GroupedMultiChoiceList: View {
    let title: String
    let groups: [(title: String, options: [String])]
    @Binding var selection: [String]

    @State private var query = ""

    var body: some View {
        List {
            ForEach(groups, id: \.title) { group in
                let options = matching(group.options)
                if !options.isEmpty {
                    Section(group.title) {
                        ForEach(options, id: \.self) { option in
                            Button {
                                toggle(option)
                            } label: {
                                HStack {
                                    Text(option.capitalizedFirst).foregroundStyle(.primary)
                                    Spacer()
                                    if selection.contains(option) {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Поиск")
        .toolbar {
            if !selection.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сбросить") { selection.removeAll() }
                }
            }
        }
    }

    private func matching(_ options: [String]) -> [String] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return options }
        return options.filter { $0.localizedCaseInsensitiveContains(text) }
    }

    private func toggle(_ option: String) {
        if let index = selection.firstIndex(of: option) {
            selection.remove(at: index)
        } else {
            selection.append(option)
        }
    }
}

extension String {
    /// The APK stores genres lowercase; they read better capitalised in a list.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

/// Free-text field (студия), styled to match the boxes around it.
@MainActor
struct TextFilterField: View {
    let title: String
    var placeholder = "Неважно"
    @Binding var text: String

    var body: some View {
        FilterFieldBox(title: title) {
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )
        }
    }
}

/// Two year boxes side by side, as the Android screen lays them out.
@MainActor
struct YearRangeField: View {
    @Binding var startYear: Int?
    @Binding var endYear: Int?

    var body: some View {
        HStack(spacing: 12) {
            yearBox("Год от", value: $startYear)
            yearBox("Год до", value: $endYear)
        }
    }

    private func yearBox(_ title: String, value: Binding<Int?>) -> some View {
        FilterFieldBox(title: title) {
            TextField("Неважно", text: Binding(
                get: { value.wrappedValue.map { String($0) } ?? "" },
                set: { value.wrappedValue = Int($0.filter(\.isNumber)) }
            ))
            .keyboardType(.numberPad)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            )
        }
    }
}
