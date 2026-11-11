import SwiftUI
import AnixartKit

/// Weekly airing schedule. Android shows one continuous week feed with a short
/// explanation, day headers and three-column poster grids; do the same here.
@MainActor
struct ScheduleView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var days: [(title: String, releases: [Release])] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @AppStorage("schedule.explanation.dismissed") private var explanationDismissed = false

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
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.section) {
                        if !explanationDismissed {
                            explanation
                        }

                        // The beta starts the week at today rather than on Monday:
                        // today first, then the days that follow, wrapping around.
                        ForEach(startingFromToday, id: \.index) { entry in
                            if !entry.day.releases.isEmpty {
                                daySection(entry.day, index: entry.index)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .refreshable { await reload() }
            }
        }
        .navigationTitle("Расписание")
        .task {
            await load()
        }
    }

    private var explanation: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.accent)
            Text("В расписании указаны дни недели, в которые выходят новые серии представленных релизов в Японии и Китае. Уже переведённые серии в озвучке и субтитрах появляются позже.")
                .font(.ax(.footnote))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button {
                explanationDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Закрыть пояснение")
        }
        .padding(14)
        .glassCard()
    }

    private func daySection(_ day: (title: String, releases: [Release]), index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(day.title)
                    .font(.ax(.title3, .semibold))
                if index == todayIndex() {
                    Text("Сегодня")
                        .font(.ax(.caption, .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.accent.opacity(0.14), in: Capsule())
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(day.releases) { release in
                    NavigationLink {
                        ReleaseDetailView(releaseID: release.id, preloaded: release)
                    } label: {
                        ReleaseCard(release: release, width: Theme.Poster.gridWidth)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var startingFromToday: [(index: Int, day: (title: String, releases: [Release]))] {
        guard !days.isEmpty else { return [] }
        let start = todayIndex() % days.count
        return (0..<days.count).map { offset in
            let index = (start + offset) % days.count
            return (index: index, day: days[index])
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

    private func reload() async {
        days = []
        await load()
    }

    /// `byWeekday` is Monday-first; `Calendar.component(.weekday:)` is Sunday-first.
    private func todayIndex() -> Int {
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: .now)
        return (weekday + 5) % 7
    }

}
