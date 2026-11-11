import SwiftUI

/// Two-finger zoom of an image where it sits (feed, posts) without opening it
/// full screen. The image springs back when the fingers lift, as in the Android beta.
private struct PinchToZoom: ViewModifier {
    @State private var scale: CGFloat = 1
    @State private var anchor: UnitPoint = .center

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale, anchor: anchor)
            .zIndex(scale > 1 ? 10 : 0)
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        anchor = value.startAnchor
                        scale = min(max(value.magnification, 1), 4)
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { scale = 1 }
                    }
            )
    }
}

extension View {
    func pinchToZoom() -> some View { modifier(PinchToZoom()) }
}
