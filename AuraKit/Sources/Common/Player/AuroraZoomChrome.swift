import Foundation

/// The zoom screens' chrome as a function of zoom, shared by every zoomable video screen: at rest
/// the border is fully visible and the picture is sharp; as soon as a pinch begins the picture
/// blurs while it grows past the frame (unbound by it — the frame itself never resizes, only
/// fades); zooming further fades the border out and lets the picture sharpen back up, ending at
/// `fillScale` with no border and a fully sharp, fully visible picture.
///
/// `fillScale` is a single tuned constant, not a per-screen, per-canvas computation of the exact
/// zoom level at which a given card's edges reach its own available area — every arrangement (the
/// Live card, Timeline detail's stacked/rail/split slots) is a different size against a different
/// canvas, and threading exact fill geometry through all of them buys a distinction nobody would
/// perceive pixel-for-pixel over a single well-chosen threshold.
public struct AuroraZoomChrome: Equatable, Sendable {
    public let borderOpacity: Double
    /// How much to blur the picture, in points — screen-space, applied to the already-scaled
    /// result, so it reads as a constant amount of "frost" regardless of zoom level rather than
    /// scaling up together with the picture.
    public let imageBlurRadius: CGFloat

    public init(scale: CGFloat, fillScale: CGFloat = 3, maxBlurRadius: CGFloat = 24) {
        // The blur ramps in over the first 30% of the zoom-to-fill range, then hands off to both
        // it and the border fading out together over the remaining 70% — border stays fully
        // opaque through the ramp so the card doesn't lose its edge the instant a pinch starts.
        let midScale = 1 + (fillScale - 1) * 0.3
        let blurIntensity: Double
        switch scale {
        case ..<1.001:
            borderOpacity = 1
            blurIntensity = 0
        case ..<midScale:
            borderOpacity = 1
            blurIntensity = Self.smoothstep(1, midScale, scale)
        default:
            let fade = 1 - Self.smoothstep(midScale, fillScale, scale)
            borderOpacity = fade
            blurIntensity = fade
        }
        imageBlurRadius = maxBlurRadius * CGFloat(blurIntensity)
    }

    private static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> Double {
        let t = Double(min(max((x - edge0) / (edge1 - edge0), 0), 1))
        return t * t * (3 - 2 * t)
    }
}
