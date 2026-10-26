import SwiftUI
import AnixartKit

/// A release poster at Anixart's 3:4 ratio, with a placeholder that keeps the
/// layout from jumping while the image loads.
@MainActor
struct ReleasePoster: View {
    let url: URL?
    var width: CGFloat = Theme.Poster.gridWidth
    var cornerRadius: CGFloat = Theme.Poster.cornerRadius

    private var height: CGFloat { width / Theme.Poster.aspectRatio }

    var body: some View {
        CachedAsyncImage(url: url, maxPixelSize: width * 2) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            placeholder(systemImage: url == nil ? "photo" : nil)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func placeholder(systemImage: String?) -> some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.ax(.title3))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Rating pill shown on posters and in the detail header.
@MainActor
struct RatingBadge: View {
    let grade: Double?
    var compact = false

    var body: some View {
        if let grade, grade > 0 {
            HStack(spacing: 2) {
                Image(systemName: "star.fill").font(.system(size: compact ? 8 : 10))
                Text(String(format: "%.1f", grade))
                    .font(compact ? .caption2 : .caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, compact ? 2 : 3)
            .background(Theme.ratingColor(grade), in: Capsule())
            .foregroundStyle(.white)
        }
    }
}

/// Small coloured dot marking which watch list a release is in.
@MainActor
struct ListStatusDot: View {
    let status: ProfileListStatus?

    var body: some View {
        if let status {
            Image(systemName: status.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(4)
                .background(Theme.accent, in: Circle())
        }
    }
}
