import SwiftUI

/// A bookmark with the squarer proportions of Material 3's icon: SF Symbols' own
/// `bookmark` is tall and narrow beside the Android one.
struct BookmarkIcon: View {
    var isFilled: Bool
    var lineWidth: CGFloat = 2

    var body: some View {
        BookmarkShape()
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .overlay { if isFilled { BookmarkShape().fill() } }
            .padding(lineWidth / 2)
    }
}

struct BookmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 3
        let notch = rect.maxY - rect.height * 0.24
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: notch))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
