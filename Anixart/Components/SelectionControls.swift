import SwiftUI

/// Both weights participate in layout, so selecting a label crossfades its weight
/// without shifting neighbouring controls or the destination of their highlight.
@MainActor
struct SelectionLabel: View {
    let title: String
    let isSelected: Bool
    var style: Font.TextStyle = .title3
    var systemImage: String? = nil
    var showsCheckmark = false

    var body: some View {
        HStack(spacing: 8) {
            if showsCheckmark {
                Image(systemName: "checkmark")
                    .font(.ax(.subheadline, .medium))
                    .opacity(isSelected ? 1 : 0)
            }
            ZStack {
                titleLabel.font(.ax(style, .regular)).opacity(isSelected ? 0 : 1)
                titleLabel.font(.ax(style, .medium)).opacity(isSelected ? 1 : 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var titleLabel: some View {
        if let systemImage { Label(title, systemImage: systemImage) }
        else { Text(title) }
    }
}

/// A persistent layout slot and an identity transition leave matched geometry in
/// charge of movement, rather than fading out one underline and fading in another.
@MainActor
struct SelectionUnderline: View {
    let isSelected: Bool
    let namespace: Namespace.ID
    var height: CGFloat = 3

    var body: some View {
        Color.clear.frame(height: height)
            .overlay {
                if isSelected {
                    Capsule().fill(Theme.selection)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                        .transition(.identity)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Only the selected fill travels between chips. Outlines remain in place and
/// the background never changes the label's size or intercepts a button press.
@MainActor
struct SelectionChipBackground<S: InsettableShape>: View {
    let isSelected: Bool
    let shape: S
    let color: Color
    let namespace: Namespace.ID

    var body: some View {
        shape.strokeBorder(.quaternary, lineWidth: 1)
            .background {
                if isSelected {
                    shape.fill(color)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                        .transition(.identity)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
