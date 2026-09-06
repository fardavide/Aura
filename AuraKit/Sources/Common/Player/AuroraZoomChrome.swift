import Foundation

/// The framed-card chrome's opacity as a function of zoom, shared by every zoomable video screen:
/// at rest the border is fully visible and the ambient glow is off; as soon as a pinch begins the
/// glow fades in; zooming further fades **both** the border and the glow together, down to zero by
/// `fillScale` — the picture reads as filling the screen with no card left to frame.
///
/// `fillScale` is a single tuned constant, not a per-screen, per-canvas computation of the exact
/// zoom level at which a given card's edges reach its own available area — every arrangement (the
/// Live card, Timeline detail's stacked/rail/split slots) is a different size against a different
/// canvas, and threading exact fill geometry through all of them buys a distinction nobody would
/// perceive pixel-for-pixel over a single well-chosen threshold.
public struct AuroraZoomChrome: Equatable, Sendable {
    public let borderOpacity: Double
    public let glassOpacity: Double

    public init(scale: CGFloat, fillScale: CGFloat = 3) {
        // The glow ramps in over the first 30% of the zoom-to-fill range, then hands off to both
        // fading out together over the remaining 70% — border stays fully opaque through the ramp
        // so the card doesn't lose its edge the instant a pinch starts.
        let midScale = 1 + (fillScale - 1) * 0.3
        switch scale {
        case ..<1.001:
            borderOpacity = 1
            glassOpacity = 0
        case ..<midScale:
            borderOpacity = 1
            glassOpacity = Self.smoothstep(1, midScale, scale)
        default:
            let fade = 1 - Self.smoothstep(midScale, fillScale, scale)
            borderOpacity = fade
            glassOpacity = fade
        }
    }

    private static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> Double {
        let t = Double(min(max((x - edge0) / (edge1 - edge0), 0), 1))
        return t * t * (3 - 2 * t)
    }
}
