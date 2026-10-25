import SwiftUI
import AnixartKit

/// The wide row the Главная tabs use (`item_release` in the APK): poster on the left,
/// then title, the episode counter and rating on one line, a description excerpt, and
/// an overflow button.
///
/// Distinct from `ReleaseRow`, which is denser and carries list-membership chips; this
/// one leads with the description because the Главная tabs are for browsing releases
/// you have not seen before.
@MainActor
struct ReleaseListRow: View {
    let release: Release
    var onOverflow: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.row) {
            ReleasePoster(url: release.posterURL, width: 92)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 4) {
                    Text(release.displayTitle)
                        .font(.title3.weight(.medium))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    if let onOverflow {
                        Button(action: onOverflow) {
                            Image(systemName: "ellipsis")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Действия с релизом")
                    }
                }

                metadata

                if let description = release.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    /// `154 из ? эп • 2.6★`, the way the Android row reads.
    @ViewBuilder
    private var metadata: some View {
        let episodes = release.episodeProgressText
        let rating = release.ratingText

        if episodes != nil || rating != nil {
            HStack(spacing: 6) {
                if let episodes {
                    Text(episodes)
                }
                if episodes != nil && rating != nil {
                    Text("•")
                }
                if let rating {
                    HStack(spacing: 2) {
                        Text(rating).monospacedDigit()
                        Image(systemName: "star.fill").font(.system(size: 9))
                    }
                    .foregroundStyle(Theme.ratingColor(release.ratingValue ?? 0))
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}
