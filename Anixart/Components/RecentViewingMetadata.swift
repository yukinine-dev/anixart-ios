import SwiftUI
import AnixartKit

/// Separate labels leave real layout space between the episode and its viewing
/// time; long text/large fonts can wrap vertically rather than crowd the separator.
struct RecentViewingMetadata: View {
    let release: Release
    let now: Date
    private var episode: String? { release.lastViewedEpisodeText }
    private var viewed: String? { ReleaseHistoryMetadata.viewedAt(release, now: now) }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let episode { Text(episode) }
                if episode != nil && viewed != nil { Text("•").foregroundStyle(.tertiary) }
                if let viewed { Text(viewed) }
            }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 6) {
                if let episode { Text(episode) }
                if let viewed { Text(viewed) }
            }
        }
        .font(.ax(.subheadline)).foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ReleaseHistoryMetadata.subtitle(release, now: now) ?? "")
    }
}

/// A stable timeline type avoids replacing navigation links on appear/background.
/// Paused schedules emit just the current snapshot, with no recurring timer.
struct RecentViewingTimelineSchedule: TimelineSchedule {
    let isActive: Bool

    func entries(from startDate: Date, mode: Mode) -> AnySequence<Date> {
        guard isActive else { return AnySequence(CollectionOfOne(startDate)) }
        return AnySequence(PeriodicTimelineSchedule(from: startDate, by: 60).entries(from: startDate, mode: mode))
    }
}
