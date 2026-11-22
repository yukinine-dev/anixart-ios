import SwiftUI

/// One card's piece of the franchise timeline: a line above (unless first), a line below
/// (unless last) and a marker in the middle, larger and in the accent color when the card
/// is the release currently open (Android's `TimelineRailView`, kind 2).
struct TimelineRail: View {
    var hasTop: Bool
    var hasBottom: Bool
    var isCurrent: Bool

    var body: some View {
        GeometryReader { geometry in
            let mid = geometry.size.height / 2
            let x = geometry.size.width / 2
            Path { path in
                if hasTop { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: mid)) }
                if hasBottom { path.move(to: CGPoint(x: x, y: mid)); path.addLine(to: CGPoint(x: x, y: geometry.size.height)) }
            }
            .stroke(Color.primary.opacity(0.2), lineWidth: 2)
            Circle()
                .fill(isCurrent ? Theme.accent : Color.primary.opacity(0.45))
                .frame(width: isCurrent ? 16 : 12, height: isCurrent ? 16 : 12)
                .position(x: x, y: mid)
        }
        .frame(width: 20)
        .accessibilityHidden(true)
    }
}
