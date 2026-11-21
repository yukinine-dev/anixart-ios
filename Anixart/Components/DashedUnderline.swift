import SwiftUI

extension View {
    /// A thin dashed line under the view, the way Android marks a link in «Подробности».
    /// Drawn by hand because `Text.underline(pattern: .dash)` cannot change the dash size.
    func dashedUnderline() -> some View {
        overlay(alignment: .bottom) {
            DashedLine()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(height: 1)
                .offset(y: 3)
        }
    }
}

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
