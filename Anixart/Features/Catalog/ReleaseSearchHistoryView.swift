import SwiftUI

@MainActor
struct ReleaseSearchHistoryView: View {
    let model: CatalogViewModel
    let history: ReleaseSearchHistoryStore
    @State private var confirmsClear = false
    @State private var feedback = 0

    var body: some View {
        Section {
            ForEach(history.entries) { entry in
                HStack(spacing: 12) {
                    Button { model.useHistory(entry) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.query).font(.ax(.body)).foregroundStyle(.primary)
                                if entry.scope.rawValue != 0 { Text(entry.scope.title).font(.ax(.caption)).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 0)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Button { if model.removeHistoryEntry(id: entry.id) { feedback += 1 } } label: {
                        Image(systemName: "xmark").font(.ax(.caption)).frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel("Удалить запрос \(entry.query) из истории")
                }
            }
        } header: {
            HStack {
                Text("История поиска").font(.ax(.subheadline)).textCase(nil)
                Spacer()
                Button("Очистить") { confirmsClear = true }.font(.ax(.subheadline))
            }
        }
        .disabled(!model.hasCurrentViewer)
        .sensoryFeedback(.selection, trigger: feedback)
        .confirmationDialog("Очистить историю поиска?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Очистить", role: .destructive) { if model.clearHistory() { feedback += 1 } }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text(history.profileID == nil
                 ? "Удалятся только запросы гостевого поиска на этом устройстве. Закладки и история просмотра не изменятся."
                 : "Удалятся только запросы из истории на этом устройстве для текущего профиля. Закладки и история просмотра не изменятся.")
        }
    }
}
