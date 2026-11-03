import SwiftUI
import AnixartKit

/// Only franchise rows use square corners; neutral colours keep all accents readable.
struct ReleaseMetadataBadge: View {
    @Environment(\.appThemePalette) private var palette
    let text: String
    var isFranchise = false

    var body: some View {
        Text(text)
            .font(.ax(.caption, .medium))
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(palette.secondaryText.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(palette.surface.color, in: RoundedRectangle(cornerRadius: isFranchise ? 0 : 5))
            .overlay(RoundedRectangle(cornerRadius: isFranchise ? 0 : 5)
                .strokeBorder(palette.secondaryText.color.opacity(0.2), lineWidth: 1))
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
