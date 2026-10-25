import SwiftUI
import AnixartKit

/// The wide row the Главная tabs use (`item_release` in the APK): poster on the left,
/// then title, the episode counter and rating on one line, and a description excerpt.
///
/// Each row is its own card so the list reads as a stack of titles rather than one
/// run of text, and the excerpt is capped at three lines so the text column stays
/// about as tall as the poster instead of stretching the row.
@MainActor
struct ReleaseListRow: View {
    let release: Release
    var onOverflow: (() -> Void)?

    private let posterWidth: CGFloat = 96

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ReleasePoster(url: release.posterURL, width: posterWidth)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(release.displayTitle)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    if let onOverflow {
                        Button(action: onOverflow) {
                            Image(systemName: "ellipsis")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 26, height: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Действия с релизом")
                    }
                }

                metadata

                if let description = release.description, !description.isEmpty {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .glassCard()
        .contentShape(Rectangle())
    }

    /// `154 из ? эп • 2.6★`, the way the Android row reads.
    @ViewBuilder
    private var metadata: some View {
        let episodes = release.episodeProgressText
        let rating = release.ratingText

        if episodes != nil || rating != nil {
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
                    .foregroundStyle(Theme.ratingColor(release.ratingValue ?? 0))
                }
            }
            .font(.subheadline)
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
