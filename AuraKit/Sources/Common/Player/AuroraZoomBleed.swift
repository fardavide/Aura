import SwiftUI

/// The ambient glow a zoomed `ZoomableContainer` casts behind its own frame — a larger, heavily
/// blurred copy of the same content, oversized and dimmed, standing in for the sharp video that
/// stops at the frame's hard edge. Feed it the transform `ZoomableContainer`'s `onTransformChange`
/// reports so the glow tracks the live gesture, not just the committed zoom.
///
/// Renders a second copy of `content` — for an `AVPlayerLayer`-backed video host this means a
/// second `AVPlayerLayer` bound to the same `AVPlayer`, which AVFoundation supports (multiple
/// layers may observe one player); it has not been checked for cost on a real device with a live
/// stream, so watch for it if the ambient glow looks or performs worse than the sharp video alone.
public struct AuroraZoomBleed<Content: View>: View {
    private let transform: ZoomTransform
    private let content: Content

    public init(transform: ZoomTransform, @ViewBuilder content: () -> Content) {
        self.transform = transform
        self.content = content()
    }

    public var body: some View {
        content
            .scaleEffect(transform.scale * Self.oversize)
            .offset(transform.offset)
            .blur(radius: 40)
            .saturation(1.2)
            .opacity(bleedOpacity)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.15), value: bleedOpacity)
    }

    /// How much larger than the sharp copy the glow renders, so it visibly extends past the
    /// frame rather than tracking it edge-for-edge.
    private static var oversize: CGFloat { 1.18 }

    /// Ramps in over the first fifth of the zoom range rather than snapping in at the first
    /// pixel of magnification, so a barely-there pinch doesn't flash a full-strength glow.
    private var bleedOpacity: Double {
        guard transform.isZoomed else { return 0 }
        let range = transform.scaleRange
        let rampSpan = (range.upperBound - range.lowerBound) * 0.2
        let progress = (transform.scale - range.lowerBound) / rampSpan
        return min(1, max(0, Double(progress)))
    }
}
