import SwiftUI
import AnixartKit

/// Only franchise rows use square corners; neutral colours keep all accents readable.
struct ReleaseMetadataBadge: View {
    @Environment(\.appThemePalette) private var palette
    let text: String
    var isFranchise = false

    var body: some View {
        // A rounded chip with room around centred text; the old square 7×4 box read
        // as cramped and off-centre next to the list text.
        Text(text)
            .font(.ax(.footnote, .medium))
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(palette.text.color.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(palette.surface.color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(palette.secondaryText.color.opacity(0.22), lineWidth: 1))
    }
}

struct ReleaseMetadataBadges: View {
    let release: Release
    var isFranchise = false

    var body: some View {
        FlowRow(spacing: 6) {
            if let category = release.categoryBadgeText { ReleaseMetadataBadge(text: category, isFranchise: isFranchise) }
        }
    }
}
