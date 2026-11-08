import SwiftUI
import AnixartKit

/// The wide row the Главная tabs use (`item_release` in the APK): poster on the left,
/// then title, the episode counter and rating on one line, and a description excerpt.
///
/// Home keeps its card surface. Posters share the original 104×156 proportions;
/// history substitutes episode/time for the excerpt.
/// Three-line excerpts keep the poster taller than the regular-size text block.
@MainActor
struct ReleaseListRow: View {
    enum Style: Equatable { case card, plain }

    let release: Release
    var style: Style = .card
    var showsSeasonAndCategory = false
    var showsDailyDiscussion = false
    var showsWatchHistory = false
    var onOverflow: (() -> Void)?

    private var posterWidth: CGFloat { 104 }

    @ViewBuilder
    var body: some View {
        if style == .card {
            content.padding(12).glassCard().contentShape(Rectangle())
        } else {
            content.contentShape(Rectangle())
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: style == .plain ? 24 : 12) {
            ReleasePoster(url: release.posterURL, width: posterWidth,
                          cornerRadius: style == .plain ? 16 : Theme.Poster.cornerRadius,
                          aspectRatio: 2.0 / 3.0)
                .overlay(alignment: .bottom) {
                    if style == .plain, let status = release.listStatus {
                        Text(status.title)
                            .font(.ax(.caption2, .medium))
                            .foregroundStyle(Theme.listColor(status))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity)
                            .background(.black.opacity(0.75), in: Capsule())
                            .padding(6)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(release.displayTitle)
                        .font(.ax(.headline))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    if let onOverflow {
                        Button(action: onOverflow) {
                            Image(systemName: "ellipsis")
                                .rotationEffect(.degrees(style == .plain ? 90 : 0))
                                .font(.ax(.subheadline))
                                .foregroundStyle(.secondary)
                                .frame(width: style == .plain ? 44 : 26, height: style == .plain ? 44 : 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Действия с релизом")
                    }
                }

                metadata
                if showsDailyDiscussion, let discussion = release.dailyDiscussionText {
                    Text(discussion).font(.ax(.caption)).foregroundStyle(.secondary)
                }

                if showsSeasonAndCategory {
                    FlowRow(spacing: 6) {
                        if let season = release.seasonAndYear {
                            ReleaseMetadataBadge(text: release.year?.isEmpty == false ? "\(season) г." : season, isFranchise: true)
                        }
                        if let category = release.categoryBadgeText {
                            ReleaseMetadataBadge(text: category, isFranchise: true)
                        }
                    }
                }

                if showsWatchHistory {
                    // Android: a red tick with «1 серия • озвучка», a teal clock with the time.
                    if let episode = release.continueWatchingText {
                        historyLine(episode.replacingOccurrences(of: " · ", with: " • "),
                                    icon: "checkmark.circle", tint: Theme.newBadge)
                            .padding(.top, 12)
                    }
                    if let date = Format.dateTime(release.lastViewedDate) {
                        historyLine(date, icon: "clock", tint: Color(red: 0.31, green: 0.78, blue: 0.72))
                            .padding(.top, 4)
                    }
                } else if let description = release.description, !description.isEmpty {
                    Text(description)
                        .font(.ax(.footnote))
                        .foregroundStyle(style == .plain ? .tertiary : .secondary)
                        .lineLimit(3)
                        .lineSpacing(style == .plain ? 3 : 0)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func historyLine(_ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(tint)
            Text(text).font(.ax(.subheadline)).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    /// `154 из ? эп • 2.6★`, the way the Android row reads.
    @ViewBuilder
    private var metadata: some View {
        let episodes = release.episodeProgressText
        let rating = release.ratingText

        if episodes != nil || rating != nil || (style == .plain && release.isFavorite == true) {
            HStack(spacing: 5) {
                if let episodes {
                    Text(episodes)
                }
                if episodes != nil && rating != nil {
                    Text("•").foregroundStyle(.tertiary)
                }
                if let rating {
                    HStack(spacing: 2) {
                        Text(rating).monospacedDigit()
                        Image(systemName: "star.fill").font(.system(size: 9))
                    }
                    .foregroundStyle(style == .plain ? Color.secondary : Theme.ratingColor(release.ratingValue ?? 0))
                }
                if style == .plain, release.isFavorite == true {
                    Image(systemName: "bookmark.fill")
                        .font(.ax(.caption))
                        .foregroundStyle(.yellow)
                }
            }
            .font(.ax(.subheadline))
            .foregroundStyle(.secondary)
        }
    }
}

/// Card background for a release row.
///
/// Liquid Glass where the toolchain and the OS both have it, a material card
/// otherwise. Two guards are needed, not one: `#available` handles the OS at runtime,
/// but `glassEffect` only exists in the iOS 26 SDK, so without the `compiler` check
/// this would not compile on an older Xcode at all.
@MainActor
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            material(content)
        }
        #else
        material(content)
        #endif
    }

    private func material(_ content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

/// Glass for a control rather than a card: a pill, for the search field and buttons.
@MainActor
struct GlassPill: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.thinMaterial, in: Capsule())
        }
        #else
        content.background(.thinMaterial, in: Capsule())
        #endif
    }
}

/// Wraps adjacent glass elements so the system can blend them into one surface
/// instead of stacking separate panes. Does nothing before iOS 26.
@MainActor
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    /// Glass on iOS 26 and up, a material card below it.
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }

    /// Glass pill, for search fields and buttons.
    func glassPill() -> some View {
        modifier(GlassPill())
    }
}
