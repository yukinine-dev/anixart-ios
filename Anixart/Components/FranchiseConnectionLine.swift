import SwiftUI

enum FranchiseConnectionGeometry {
    // Plain franchise row: 16pt inset, 104x156 poster.
    static let x: CGFloat = 68
    static let posterCentreY: CGFloat = 94

    static func segment(height: CGFloat, first: Bool, last: Bool) -> ClosedRange<CGFloat> {
        let height = max(0, height)
        let centre = min(height, posterCentreY)
        return (first ? centre : 0)...(last ? centre : height)
    }
}

@MainActor
struct FranchiseConnectionLine: View {
    var visible: Bool
    var first: Bool
    var last: Bool

    var body: some View {
        GeometryReader { geometry in
            if visible {
                let segment = FranchiseConnectionGeometry.segment(height: geometry.size.height, first: first, last: last)
                Rectangle().fill(Theme.accent)
                    .frame(width: 2, height: segment.upperBound - segment.lowerBound)
                    .position(x: FranchiseConnectionGeometry.x, y: (segment.lowerBound + segment.upperBound) / 2)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
