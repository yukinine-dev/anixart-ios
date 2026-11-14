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

    static let posterHeight: CGFloat = 372
    static let backdropHeight: CGFloat = 412
    /// How far the backdrop reaches above the page, behind the bars.
    static let backdropExtension: CGFloat = 240

    @State private var tint = PosterTint.neutral

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Android paints a gradient pulled from the poster's own colors behind
            // the whole top of the page, up under the status bar -- not a blur --
            // and the poster over it; the bar above is transparent.
            ZStack {
                CachedAsyncImage(url: release.posterURL, maxPixelSize: 760) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 28).fill(.quaternary)
                        .frame(width: Self.posterHeight * 2 / 3)
                }
                .frame(height: Self.posterHeight)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
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
                    LinearGradient(colors: [tint.top.opacity(0.82), tint.bottom.opacity(0.92)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .bottom) {
                    // Dissolves the tint into the page background so the title block
                    // below starts on a seamless surface, with no visible edge.
                    LinearGradient(stops: [
                        .init(color: palette.background.color.opacity(0), location: 0),
                        .init(color: palette.background.color.opacity(0.55), location: 0.55),
                        .init(color: palette.background.color, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                        .frame(height: (Self.backdropHeight + Self.backdropExtension) * 0.5)
                }
                .clipped()
                .task(id: release.posterURL) {
                    guard let url = release.posterURL,
                          let image = await ImageLoader.shared.image(for: url, pixelSize: 48) else { return }
                    let sampled = PosterColorExtractor.tint(of: image)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.25)) { tint = sampled }
                }
            }
            .accessibilityHidden(true)

            Button(action: onTitles) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text(release.displayTitle)
                            .font(.ax(.title2, .bold))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let subtitle = release.displaySubtitle {
                            Text(subtitle).font(.ax(.subheadline)).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let age = release.ageRatingText {
                            Text(age)
                                .font(.ax(.caption2, .medium))
                                .foregroundStyle(palette.background.color)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(palette.text.color, in: RoundedRectangle(cornerRadius: 3))
                                .fixedSize()
                                .accessibilityLabel("Возрастное ограничение: \(age)")
                        }
                    }
                    .padding(.leading, 32)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityLabel("Названия релиза: \(release.displayTitle)")
            .accessibilityValue(release.ageRatingText ?? "")
            .padding(.horizontal)
            .padding(.top, Theme.Spacing.row)
        }
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
            if !isExpanded && isTruncated {
                Button("Подробнее") { expand(fromKeyboard: false) }
                    .font(.ax(.headline, .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .buttonStyle(.plain)
                    .onKeyPress(.return) { expand(fromKeyboard: true); return .handled }
                    .onKeyPress(.space) { expand(fromKeyboard: true); return .handled }
            }
        }
        .onPreferenceChange(ReleaseTextHeightPreference.self) { heights in
            isTruncated = ReleaseTextTruncation.needsExpansion(fullHeight: heights["full"] ?? 0, visibleHeight: heights["visible"] ?? 0)
        }
    }

    private func expand(fromKeyboard: Bool) {
        if let onExpand { onExpand(fromKeyboard) } else { isExpanded = true }
    }
}
