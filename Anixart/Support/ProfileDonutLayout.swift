import Foundation
import CoreGraphics

enum ProfileDonutLayout {
    struct Span: Equatable {
        let start: CGFloat
        let end: CGFloat
        var length: CGFloat { end - start }
    }

    /// Counts remain exact in the legend. A minimum visual arc keeps nonzero
    /// counts visible; gaps shrink with the slice instead of deleting small values.
    static func spans(values: [Int], minimumFraction: CGFloat = 0.003) -> [Span] {
        let counts = values.map { Double(max(0, $0)) }
        let total = counts.reduce(0, +)
        guard total.isFinite, total > 0 else { return [] }
        let positive = counts.filter { $0 > 0 }.count
        let requested = minimumFraction.isFinite ? max(0, minimumFraction) : 0.003
        let minimum = min(requested, 1 / CGFloat(max(1, positive)))
        let weights = counts.map { $0 > 0 ? max(CGFloat($0 / total), minimum) : 0 }
        let weightTotal = weights.reduce(0, +)
        var cursor: CGFloat = 0
        return weights.map { weight in
            let fraction = weight / weightTotal
            let gap = positive > 1 ? min(0.004, fraction * 0.12) : 0
            let start = min(1, max(0, cursor + gap / 2))
            let span = Span(start: start, end: max(start, min(1, cursor + fraction - gap / 2)))
            cursor = min(1, cursor + fraction)
            return span
        }
    }
}
