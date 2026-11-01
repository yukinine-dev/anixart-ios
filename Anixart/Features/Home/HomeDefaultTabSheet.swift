import SwiftUI

@MainActor
struct HomeDefaultTabSheet: View {
    @Environment(\.dismiss) private var dismiss
    let preferences: HomePreferences

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Выбранная вкладка будет открываться при запуске приложения")
                        .font(.ax(.subheadline)).foregroundStyle(.secondary)
                }
                ForEach(HomeTab.allCases) { tab in
                    Button {
                        preferences.setDefaultTab(tab)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tab == .custom ? preferences.customTabTitle : tab.title).font(.ax(.headline))
                                Text(tab.summary).font(.ax(.subheadline)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if preferences.defaultTab == tab {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Изменить вкладку по умолч.")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
        }
    }
}
