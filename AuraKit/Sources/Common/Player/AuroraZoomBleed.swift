import SwiftUI

/// The ambient glow a zoomed `ZoomableContainer` casts behind its own frame — a larger, heavily
/// blurred copy of the same content, oversized and dimmed, standing in for the sharp video that
/// stops at the frame's hard edge. Feed it the transform `ZoomableContainer`'s `onTransformChange`
/// reports so the glow tracks the live gesture, not just the committed zoom; `opacity` comes from
/// `AuroraZoomChrome.glassOpacity`, shared with the frame's own border fade so both move together.
///
/// Renders a second copy of `content` — for an `AVPlayerLayer`-backed video host this means a
/// second `AVPlayerLayer` bound to the same `AVPlayer`, which AVFoundation supports (multiple
/// layers may observe one player); it has not been checked for cost on a real device with a live
/// stream, so watch for it if the ambient glow looks or performs worse than the sharp video alone.
///
/// Must sit **outside** any clip shape the frame around it draws (e.g. `auroraFrame`'s rounded-rect
/// clip) — added as that frame's `.background` (after it in the modifier chain), not before, or the
/// frame's own clip silently cuts the oversized glow down to its own bounds and it never shows.
public struct AuroraZoomBleed<Content: View>: View {
    private let opacity: Double
    private let transform: ZoomTransform
    private let content: Content

    public init(opacity: Double, transform: ZoomTransform, @ViewBuilder content: () -> Content) {
        self.opacity = opacity
        self.transform = transform
        self.content = content()
    }

    public var body: some View {
        content
            .scaleEffect(transform.scale * Self.oversize)
            .offset(transform.offset)
            .blur(radius: 40)
            .saturation(1.2)
            .opacity(opacity)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.15), value: opacity)
    }

    /// How much larger than the sharp copy the glow renders, so it visibly extends past the
    /// frame rather than tracking it edge-for-edge.
    private static var oversize: CGFloat { 1.18 }
}
