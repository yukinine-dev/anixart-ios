import SwiftUI
import AnixartKit

/// Square-cornered status/type labels use the selected light/dark theme.
struct ReleaseMetadataBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.ax(.caption, .medium))
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Theme.selection, in: Rectangle())
            .overlay(Rectangle().strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1))
    }
}

struct ReleaseMetadataBadges: View {
    let release: Release

    var body: some View {
        FlowRow(spacing: 6) {
            if let status = release.statusBadgeText { ReleaseMetadataBadge(text: status) }
            if let category = release.categoryBadgeText { ReleaseMetadataBadge(text: category) }
        }
    }
}
