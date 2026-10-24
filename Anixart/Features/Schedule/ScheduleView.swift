import SwiftUI
import AnixartKit

/// Weekly airing schedule. The whole week arrives in one response, so this screen
/// loads once and then just switches the selected day.
@MainActor
struct ScheduleView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var days: [(title: String, releases: [Release])] = []
    @State private var selectedDay = 0
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && days.isEmpty {
                ProgressView()
            } else if let errorMessage, days.isEmpty {
                StatusMessageView(
                    title: "Не удалось загрузить расписание",
                    message: errorMessage,
                    systemImage: "wifi.exclamationmark",
                    retry: { await load() }
                )
            } else {
                VStack(spacing: 0) {
                    Picker("День", selection: $selectedDay) {
                        ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                            Text(shortTitle(day.title)).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    List {
                        if days.indices.contains(selectedDay) {
                            let day = days[selectedDay]
                            if day.releases.isEmpty {
                                Text("В этот день ничего не выходит")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(day.releases) { release in
                                    NavigationLink {
                                        ReleaseDetailView(releaseID: release.id, preloaded: release)
                                    } label: {
                                        ReleaseRow(release: release)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationTitle("Расписание")
        .task {
            selectedDay = todayIndex()
            await load()
        }
    }

    private func load() async {
        guard days.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await env.client.send(CatalogEndpoints.schedule())
            days = response.byWeekday
        } catch {
            errorMessage = Paginator<Release>.message(for: error)
        }
        isLoading = false
    }

    /// `byWeekday` is Monday-first; `Calendar.component(.weekday:)` is Sunday-first.
    private func todayIndex() -> Int {
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: .now)
        return (weekday + 5) % 7
    }

    private func shortTitle(_ title: String) -> String {
        String(title.prefix(2))
    }
}
