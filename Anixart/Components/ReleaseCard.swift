import SwiftUI
import AnixartKit

/// Poster-and-title cell used by the grids and horizontal carousels.
@MainActor
struct ReleaseCard: View {
    let release: Release
    var width: CGFloat = Theme.Poster.gridWidth

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                ReleasePoster(url: release.posterURL, width: width)
                HStack(spacing: 4) {
                    RatingBadge(grade: release.ratingValue, compact: true)
                    if release.isFavorite == true {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(.pink, in: Circle())
                    }
                }
                .padding(5)
            }

            Text(release.displayTitle)
                .font(.ax(.caption))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: width, alignment: .leading)

            if let detail = release.episodeProgressText ?? release.seasonAndYear {
                Text(detail)
                    .font(.ax(.caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Wide row used by lists: poster on the left, metadata on the right.
@MainActor
struct ReleaseRow: View {
    let release: Release
    var showContinueWatching = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.row) {
            ReleasePoster(url: release.posterURL, width: Theme.Poster.rowWidth)

            VStack(alignment: .leading, spacing: 4) {
                Text(release.displayTitle)
                    .font(.ax(.subheadline, .medium))
                    .lineLimit(2)

                if let subtitle = release.displaySubtitle {
                    Text(subtitle)
                        .font(.ax(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    RatingBadge(grade: release.ratingValue)
                    if let progress = release.episodeProgressText {
                        Label(progress, systemImage: "film")
                            .labelStyle(.compact)
                    }
                    if let seasonYear = release.seasonAndYear {
                        Text(seasonYear)
                    }
                }
                .font(.ax(.caption))
                .foregroundStyle(.secondary)

                if showContinueWatching, let text = release.continueWatchingText {
                    Label(text, systemImage: "play.circle.fill")
                        .labelStyle(.compact)
                        .font(.ax(.caption))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                }

                if let status = release.listStatus {
                    Text(status.title)
                        .font(.ax(.caption2, .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.15), in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Icon and title on one line with tight spacing, for dense metadata rows.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

extension LabelStyle where Self == CompactLabelStyle {
    static var compact: CompactLabelStyle { CompactLabelStyle() }
}
