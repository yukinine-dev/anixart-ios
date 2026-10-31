import SwiftUI
import AnixartKit

/// Parameters from Android's ThemedContainerLayout, expressed in display points.
/// Its density, size and translation speeds are specified in raw pixels.
struct ProfileThemeLayout {
    enum BackgroundMode: String {
        case centerCrop = "center_crop", fitXY = "fit_xy", tile
        init(_ value: String?) { self = Self(rawValue: value?.lowercased() ?? "") ?? .centerCrop }
    }

    enum GradientDirection: String, CaseIterable {
        case leftToRight = "left_to_right", topToBottom = "top_to_bottom", bottomToTop = "bottom_to_top"
        case diagonalTLBR = "diagonal_tl_br", diagonalTRBL = "diagonal_tr_bl", radial = "radial_from_center"
        init(_ value: String?) { self = Self(rawValue: value?.lowercased() ?? "") ?? .topToBottom }

        var endpoints: (start: UnitPoint, end: UnitPoint) {
            switch self {
            case .leftToRight: return (UnitPoint(x: 0, y: 0), UnitPoint(x: 1, y: 0))
            case .topToBottom: return (UnitPoint(x: 0, y: 0), UnitPoint(x: 0, y: 1))
            case .bottomToTop: return (UnitPoint(x: 0, y: 1), UnitPoint(x: 0, y: 0))
            case .diagonalTLBR: return (.topLeading, .bottomTrailing)
            case .diagonalTRBL: return (.topTrailing, .bottomLeading)
            case .radial: return (.center, .center)
            }
        }
    }

    let theme: ProfileTheme

    var density: CGFloat {
        switch theme.themeIconDensity?.lowercased() {
        case "low": return 0.02
        case "high": return 0.07
        default: return 0.04
        }
    }

    var pixelSizeRange: Range<Int> {
        switch theme.themeIconSize?.lowercased() {
        case "small": return 25..<55
        case "large": return 70..<140
        case "ultra": return 150..<250
        default: return 40..<90
        }
    }

    var speedMultiplier: Double {
        switch theme.themeAnimationSpeed?.lowercased() {
        case "medium": return 5
        case "high": return 10
        case "ultra": return 50
        default: return 1
        }
    }

    static func alpha(_ value: Double?, fallback: Double) -> Double {
        guard let value, value.isFinite else { return fallback }
        return min(1, max(0, value))
    }

    static func radialRadius(for size: CGSize) -> CGFloat {
        hypot(size.width / 2, size.height / 2) * 0.8
    }

    static func backgroundRect(imageSize: CGSize, container: CGSize, mode: BackgroundMode) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, imageSize.width.isFinite, imageSize.height.isFinite,
              container.width > 0, container.height > 0, container.width.isFinite, container.height.isFinite else { return .zero }
        guard mode == .centerCrop else { return CGRect(origin: .zero, size: container) }
        let scale = max(container.width / imageSize.width, container.height / imageSize.height)
        let width = imageSize.width * scale, height = imageSize.height * scale
        return CGRect(x: (container.width - width) / 2, y: (container.height - height) / 2, width: width, height: height)
    }

    static func tileScale(sourceSize: CGSize, decodedSize: CGSize, displayScale: CGFloat) -> CGFloat {
        guard sourceSize.width > 0, sourceSize.width.isFinite,
              decodedSize.width > 0, decodedSize.width.isFinite else { return 1 }
        let scale = displayScale.isFinite ? max(1, displayScale) : 1
        return sourceSize.width / decodedSize.width / scale
    }

    func particles(in size: CGSize, displayScale: CGFloat) -> [ProfileThemeParticle] {
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return [] }
        let scale = displayScale.isFinite ? max(1, displayScale) : 1
        // A malformed size must never turn a decorative background into an
        // unbounded allocation. Real showcases need only a few dozen particles.
        let count = Int(min(256, max(1, size.height * scale * density)))
        var random = ProfileThemeRandom(seed: UInt64(truncatingIfNeeded: theme.id))
        let range = pixelSizeRange
        let alpha = Self.alpha(theme.themeIconAlpha, fallback: 0.5)
        return (0..<count).map { _ in
            let origin = CGPoint(x: random.unit() * size.width, y: random.unit() * size.height)
            let rotation = (random.unit() - 0.5) * 60
            let pixels = range.lowerBound + Int(random.unit() * CGFloat(range.count))
            let opacity = Double(random.unit()) * alpha
            let speed = CGFloat(speedMultiplier) / scale
            return ProfileThemeParticle(origin: origin, rotation: Double(rotation), size: CGFloat(pixels) / scale,
                                        opacity: opacity,
                                        velocity: CGVector(dx: (random.unit() - 0.5) * 30 * speed,
                                                           dy: (random.unit() - 0.5) * 30 * speed),
                                        rotationSpeed: Double((random.unit() - 0.5) * 15) * speedMultiplier)
        }
    }
}

struct ProfileThemeParticle: Equatable {
    let origin: CGPoint
    let rotation: Double
    let size: CGFloat
    let opacity: Double
    let velocity: CGVector
    let rotationSpeed: Double

    func position(at elapsed: TimeInterval, in container: CGSize) -> CGPoint {
        let time = CGFloat(max(0, elapsed.isFinite ? elapsed : 0))
        return CGPoint(x: Self.wrap(origin.x + velocity.dx * time, extent: container.width, margin: size),
                       y: Self.wrap(origin.y + velocity.dy * time, extent: container.height, margin: size))
    }

    private static func wrap(_ value: CGFloat, extent: CGFloat, margin: CGFloat) -> CGFloat {
        let period = extent + 2 * margin
        guard period > 0 else { return 0 }
        let remainder = (value + margin).truncatingRemainder(dividingBy: period)
        return (remainder < 0 ? remainder + period : remainder) - margin
    }
}

/// Deterministic positions survive SwiftUI body evaluations and theme refreshes.
private struct ProfileThemeRandom {
    var seed: UInt64
    mutating func unit() -> CGFloat {
        seed &+= 0x9E3779B97F4A7C15
        var value = seed
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return CGFloat(Double(value >> 11) / Double(UInt64(1) << 53))
    }
}

struct ProfileThemeMotionClock {
    private(set) var accumulated: TimeInterval = 0
    private(set) var startedAt: Date?

    mutating func setRunning(_ running: Bool, at date: Date) {
        if running, startedAt == nil { startedAt = date }
        else if !running, let startedAt {
            accumulated += max(0, date.timeIntervalSince(startedAt))
            self.startedAt = nil
        }
    }

    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (startedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }
}

/// Particle translation is a preference, not a switch for a theme's GIFs.
/// Visibility, scene activity and Reduce Motion pause both kinds of animation.
struct ProfileThemeAnimationState: Equatable {
    let isVisible: Bool
    let isSceneActive: Bool
    let reduceMotion: Bool
    let particleMotionEnabled: Bool

    var texturesRunning: Bool { isVisible && isSceneActive && !reduceMotion }
    var particlesRunning: Bool { texturesRunning && particleMotionEnabled }
}

enum ProfileThemeColor {
    struct RGBA: Equatable {
        let red: Double, green: Double, blue: Double, alpha: Double
        var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
    }

    /// Android accepts #RRGGBB, #AARRGGBB (alpha first), and its named colours.
    static func components(_ value: String?) -> RGBA? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let number: UInt64
        if text.hasPrefix("#") {
            let hex = text.dropFirst()
            guard (hex.count == 6 || hex.count == 8), let parsed = UInt64(hex, radix: 16) else { return nil }
            number = hex.count == 6 ? parsed | 0xFF000000 : parsed
        } else {
            let names: [String: UInt64] = [
                "black": 0xFF000000, "darkgray": 0xFF444444, "darkgrey": 0xFF444444,
                "gray": 0xFF888888, "grey": 0xFF888888, "lightgray": 0xFFCCCCCC, "lightgrey": 0xFFCCCCCC,
                "white": 0xFFFFFFFF, "red": 0xFFFF0000, "green": 0xFF00FF00, "lime": 0xFF00FF00,
                "blue": 0xFF0000FF, "yellow": 0xFFFFFF00, "cyan": 0xFF00FFFF, "aqua": 0xFF00FFFF,
                "magenta": 0xFFFF00FF, "fuchsia": 0xFFFF00FF, "maroon": 0xFF800000,
                "navy": 0xFF000080, "olive": 0xFF808000, "purple": 0xFF800080,
                "silver": 0xFFC0C0C0, "teal": 0xFF008080
            ]
            guard let named = names[text.lowercased()] else { return nil }
            number = named
        }
        return RGBA(red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255,
                    blue: Double(number & 255) / 255, alpha: Double((number >> 24) & 255) / 255)
    }

    static func color(_ value: String?) -> Color? { components(value)?.color }
}
