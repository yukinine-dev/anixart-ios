import SwiftUI
import AnixartKit

/// Poster precedes its metadata; the description starts beside it, not below it.
@MainActor
struct ReleaseDetailHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let release: Release
    @Binding var isDescriptionExpanded: Bool
    let onTitles: () -> Void
    let onExpand: (Bool) -> Void

    var body: some View {
        ReleaseHeaderLayout(largeText: dynamicTypeSize >= .xxxLarge) {
            VStack(alignment: .leading, spacing: 8) {
                ReleasePoster(url: release.posterURL, width: 148)
                    .accessibilityHidden(true)
                Button(action: onTitles) {
                    Label {
                        Text(release.displayTitle)
                            .font(.ax(.title3, .bold))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .accessibilityLabel("Названия релиза: \(release.displayTitle)")

                if let subtitle = release.displaySubtitle {
                    Text(subtitle).font(.ax(.caption)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                FlowRow(spacing: 8) {
                    if let episodes = release.episodeProgressText { Text(episodes) }
                    if let rating = release.ratingText { Label(rating, systemImage: "star.fill").monospacedDigit() }
                    if let age = release.ageRatingText { ReleaseMetadataBadge(text: age) }
                }
                .font(.ax(.subheadline))
                .foregroundStyle(.secondary)
                ReleaseMetadataBadges(release: release)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let description = release.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                ReleaseExpandableText(text: description, lineLimit: 10, isExpanded: $isDescriptionExpanded, onExpand: onExpand)
            }
        }
        .padding(.horizontal)
        .padding(.top, Theme.Spacing.row)
    }
}

/// Measures both columns from the same top edge and stacks for narrow/large text.
struct ReleaseHeaderLayout: Layout {
    var largeText = false
    static let spacing: CGFloat = 16
    static let minimumColumnWidth: CGFloat = 324

    static func usesColumns(availableWidth: CGFloat, largeText: Bool) -> Bool {
        availableWidth >= minimumColumnWidth && !largeText
    }

    private func columnWidths(_ width: CGFloat, count: Int) -> (CGFloat, CGFloat?) {
        guard count > 1, Self.usesColumns(availableWidth: width, largeText: largeText) else { return (width, nil) }
        let metadata = max(148, min(208, width * 0.42))
        return (metadata, width - metadata - Self.spacing)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let first = subviews.first else { return .zero }
        let width = proposal.width ?? Self.minimumColumnWidth
        let columns = columnWidths(width, count: subviews.count)
        let metadata = first.sizeThatFits(ProposedViewSize(width: columns.0, height: nil))
        guard subviews.count > 1 else { return CGSize(width: width, height: metadata.height) }
        let description = subviews[1].sizeThatFits(ProposedViewSize(width: columns.1 ?? width, height: nil))
        let height = columns.1 == nil ? metadata.height + Self.spacing + description.height : max(metadata.height, description.height)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let first = subviews.first else { return }
        let columns = columnWidths(bounds.width, count: subviews.count)
        let metadataProposal = ProposedViewSize(width: columns.0, height: nil)
        first.place(at: bounds.origin, anchor: .topLeading, proposal: metadataProposal)
        guard subviews.count > 1 else { return }
        let origin: CGPoint
        if columns.1 != nil {
            origin = CGPoint(x: bounds.minX + columns.0 + Self.spacing, y: bounds.minY)
        } else {
            origin = CGPoint(x: bounds.minX, y: bounds.minY + first.sizeThatFits(metadataProposal).height + Self.spacing)
        }
        subviews[1].place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(width: columns.1 ?? bounds.width, height: nil))
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
                Button("Подробнее…") { expand(fromKeyboard: false) }
                    .font(.ax(.subheadline, .medium))
                    .foregroundStyle(Theme.accent)
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
