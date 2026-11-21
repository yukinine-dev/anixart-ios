import SwiftUI
import AnixartKit

/// Original detail order: large centred poster, title and original name with age.
@MainActor
struct ReleaseDetailHeader: View {
    @Environment(\.appThemePalette) private var palette
    let release: Release
    let onTitles: () -> Void
    /// Opens the poster full screen, where it can be zoomed and saved.
    var onPoster: (() -> Void)?
    /// Only the original-name color comes from the poster; the backdrop is the poster itself.
    @State private var accent: Color?
    @State private var ageBadge: UIImage?
    @Environment(\.displayScale) private var displayScale

    static let posterHeight: CGFloat = 372
    static let backdropHeight: CGFloat = 412
    /// How far the whole block is lifted so the poster starts right under the status bar.
    static let topLift: CGFloat = 0
    /// How far the backdrop reaches above the page, behind the bars.
    static let backdropExtension: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Android paints the poster itself, enlarged and heavily dimmed, behind the
            // whole top of the page and the poster sharp over it; the bar above is transparent.
            ZStack {
                CachedAsyncImage(url: release.posterURL, maxPixelSize: 760) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 28).fill(.quaternary)
                        .frame(width: Self.posterHeight * 2 / 3)
                }
                .frame(height: Self.posterHeight)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                // Android outlines the poster with a thin light line.
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .onTapGesture { onPoster?() }
                .accessibilityAddTraits(onPoster == nil ? [] : .isButton)
                .accessibilityLabel("Постер")
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.backdropHeight)
            .background(alignment: .bottom) {
                // Inside a scroll view the safe area does not reach above the content,
                // so the backdrop is simply made taller upwards, under status and nav bars.
                CachedAsyncImage(url: release.posterURL, maxPixelSize: 760) { image in
                    image.resizable().scaledToFill()
                } placeholder: { Color.clear }
                .frame(maxWidth: .infinity)
                .frame(height: Self.backdropHeight + Self.backdropExtension)
                .clipped()
                .overlay {
                    // Measured on a live Android screen: the backdrop is the poster itself,
                    // sharp (no blur), dimmed to roughly 21% of the poster's brightness (beta 3, a live capture).
                    palette.background.color.opacity(0.78)
                }
                .overlay(alignment: .bottom) {
                    // Dissolves the tint into the page background so the title block
                    // below starts on a seamless surface, with no visible edge.
                    // Measured on Android: the ghost stays flat to ~35% of the screen,
                    // then is gone by ~45%.
                    LinearGradient(stops: [
                        .init(color: palette.background.color.opacity(0), location: 0),
                        .init(color: palette.background.color, location: 0.8)
                    ], startPoint: .top, endPoint: .bottom)
                        .frame(height: 150)
                }
                .clipped()
            }
            .accessibilityHidden(true)
            .task(id: release.posterURL) {
                guard let url = release.posterURL,
                      let thumbnail = await ImageLoader.shared.image(for: url, pixelSize: 64) else { return }
                accent = PosterColorExtractor.dominantAccent(of: thumbnail)
            }
            .task(id: release.ageRatingText) { renderAgeBadge() }

            Button(action: onTitles) {
                // Beta 3: the title block is centred, the age rating is an outlined
                // chip beside the title, and the original name takes the poster's color.
                VStack(spacing: 6) {
                    // The age chip sits inline after the last word of the title, so a title that
                    // wraps carries it on its last line (as on Android), not in a column of its own.
                    titleWithBadge
                        .font(.ax(.title2, .bold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = release.displaySubtitle {
                        HStack(spacing: 6) {
                            Text(subtitle).lineLimit(1)
                            Image(systemName: "chevron.right").font(.ax(.caption, .semibold))
                        }
                        .font(.ax(.callout))
                        .foregroundStyle(accent ?? Color.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityLabel("Названия релиза: \(release.displayTitle)")
            .accessibilityValue(release.ageRatingText ?? "")
            .padding(.horizontal)
            .padding(.top, Theme.Spacing.row)
        }
        // Android's poster starts right under the status bar, with the round buttons
        // beside it; here the page starts below the nav bar, so lift the whole block
        // (measured: ~62pt lower than Android on a live comparison).
        .padding(.top, -Self.topLift)
    }
}

extension ReleaseDetailHeader {
    /// Title text with the age chip appended as an inline image; the bare title until the
    /// chip has been rendered, or when the release has no rating.
    fileprivate var titleWithBadge: Text {
        var text = Text(release.displayTitle)
        if let ageBadge {
            text = text + Text(" ") + Text(Image(uiImage: ageBadge).renderingMode(.original)).baselineOffset(-5)
        }
        return text
    }

    fileprivate func renderAgeBadge() {
        guard let age = release.ageRatingText else { ageBadge = nil; return }
        let renderer = ImageRenderer(content: AgeRatingChip(text: age, color: palette.text.color))
        renderer.scale = displayScale
        ageBadge = renderer.uiImage
    }
}

/// The outlined «16+» chip, drawn once to an image so it can sit inside a line of text.
private struct AgeRatingChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(color.opacity(0.75), lineWidth: 1.5))
            .padding(1.5)
    }
}

enum ReleaseTextTruncation {
    static func needsExpansion(fullHeight: CGFloat, visibleHeight: CGFloat) -> Bool {
        visibleHeight > 0 && fullHeight > visibleHeight + 1
    }
}

private struct ReleaseTextHeightPreference: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Show “Подробнее” only when the measured text really has hidden lines.
struct ReleaseExpandableText: View {
    let text: String
    var lineLimit = 10
    var alignment: TextAlignment = .leading
    @Binding var isExpanded: Bool
    var onExpand: ((Bool) -> Void)?
    @State private var isTruncated = false
    /// Latched once the text has been seen truncated, so «Скрыть» stays after opening.
    @State private var canCollapse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fullText: some View {
        Text(text).font(.ax(.subheadline)).lineSpacing(3)
            .multilineTextAlignment(alignment)
    }

    var body: some View {
        VStack(alignment: alignment == .center ? .center : .leading, spacing: 12) {
            fullText
                .lineLimit(isExpanded ? nil : lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: ReleaseTextHeightPreference.self, value: ["visible": geometry.size.height])
                    }
                }
                .background {
                    fullText.lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                        .hidden().accessibilityHidden(true)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: ReleaseTextHeightPreference.self, value: ["full": geometry.size.height])
                            }
                        }
                }
            // Once the text is known to be longer than its collapsed height, the
            // same spot offers «Подробнее…» to open it and «Скрыть» to close it again.
            if isTruncated || canCollapse {
                Button(isExpanded ? "Скрыть" : "Подробнее…") {
                    if isExpanded { collapse() } else { expand(fromKeyboard: false) }
                }
                    .font(.ax(.headline, .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .buttonStyle(.plain)
                    .onKeyPress(.return) { if isExpanded { collapse() } else { expand(fromKeyboard: true) }; return .handled }
                    .onKeyPress(.space) { if isExpanded { collapse() } else { expand(fromKeyboard: true) }; return .handled }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86), value: isExpanded)
        .onPreferenceChange(ReleaseTextHeightPreference.self) { heights in
            let needs = ReleaseTextTruncation.needsExpansion(fullHeight: heights["full"] ?? 0, visibleHeight: heights["visible"] ?? 0)
            isTruncated = needs
            if needs { canCollapse = true }
        }
    }

    private func expand(fromKeyboard: Bool) {
        if let onExpand { onExpand(fromKeyboard) } else { isExpanded = true }
    }

    private func collapse() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) { isExpanded = false }
    }
}
