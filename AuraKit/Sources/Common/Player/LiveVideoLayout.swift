import SwiftUI

import CommonDesign

/// The live view's on-screen composition, one view tree whose two `LiveVideoArrangement`s differ
/// only in values (never a second `body` branch — see the type's own doc comment for why): a
/// framed 16:9 card centred on the aurora background with the controls floating below it
/// (`.card`), or the video filling the screen **behind** the safe area with the transport controls
/// overlaid **inside** it (`.fill`). In `.card` the controls sit in a bottom safe-area inset, so
/// the canvas the card is measured against already excludes them; in `.fill` the video ignores
/// that inset and runs full-bleed under it, as it always has. Split out from `LiveVideoView` so
/// this layout can be snapshot-tested with a placeholder video and a fixed control state, without
/// constructing a real player.
public struct LiveVideoLayout<Video: View>: View {
    private let arrangement: LiveVideoArrangement
    private let controls: LiveControlBar
    private let areControlsVisible: Bool
    private let onSingleTap: () -> Void
    private let video: Video

    /// The live transform `ZoomableContainer` reports, fed to `AuroraZoomChrome` for the border
    /// fade and picture blur. `@State`, not a local in `videoSurface`, so it survives that view's
    /// own re-evaluation without resetting mid-gesture.
    @State private var zoomTransform = ZoomTransform.standard()

    public init(
        arrangement: LiveVideoArrangement,
        controls: LiveControlBar,
        areControlsVisible: Bool,
        onSingleTap: @escaping () -> Void,
        @ViewBuilder video: () -> Video
    ) {
        self.arrangement = arrangement
        self.controls = controls
        self.areControlsVisible = areControlsVisible
        self.onSingleTap = onSingleTap
        self.video = video()
    }

    public var body: some View {
        GeometryReader { geo in
            let metrics = arrangement.metrics(canvas: geo.size)
            ZStack(alignment: .topLeading) {
                videoSurface(metrics)
                AuroraLivePill(style: .glass)
                    .padding(.leading, metrics.livePillInset.x)
                    .padding(.top, metrics.livePillInset.y)
                    .opacity(areControlsVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: areControlsVisible)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            controls
                .padding(.bottom, arrangement.controlsBottomInset)
                .opacity(areControlsVisible ? 1 : 0)
                .allowsHitTesting(areControlsVisible)
                .animation(.easeInOut(duration: 0.2), value: areControlsVisible)
        }
        .auroraBackground()
    }

    /// The card's border is a fixed-size, non-clipping overlay (`AuroraZoomFrame`) — it never
    /// resizes — so the picture underneath is free to grow past it: `ZoomableContainer` gets no
    /// explicit frame of its own here, so it expands to this whole surface's canvas (via the
    /// enclosing `ZStack`'s `.frame(maxWidth: .infinity, maxHeight: .infinity)` in `body`) and
    /// clips only at that outer boundary, while `video` inside it is sized to the card's rest
    /// dimensions — at scale 1 that reads as a card; scaled up by a pinch, the same picture grows
    /// past where the (fading, motionless) rim sits, eventually filling the whole canvas.
    ///
    /// The blur is only ever visible in the picture that's grown *past* the card's rest-state rect
    /// — not the whole picture. A non-interactive mirror of the same content, scaled and panned
    /// identically to the real one, sits behind it blurred and full-canvas; the real, sharp,
    /// gesture-driving `ZoomableContainer` sits in front, masked down to just the card's own rect,
    /// so the sharp copy is all that shows there and the blurred mirror only shows through where
    /// the picture has grown beyond it.
    private func videoSurface(_ metrics: LiveVideoMetrics) -> some View {
        let chrome = AuroraZoomChrome(scale: zoomTransform.scale)
        return ZStack {
            video
                .frame(width: metrics.videoSize?.width, height: metrics.videoSize?.height)
                .background(.black)
                // Rounded to match the sharp layer's own clip and its mask — otherwise the
                // blurred backdrop's square corners peek past the border's rounded ones.
                .clipShape(RoundedRectangle(cornerRadius: metrics.videoCornerRadius * chrome.borderOpacity, style: .continuous))
                .scaleEffect(zoomTransform.scale)
                .offset(zoomTransform.offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .blur(radius: chrome.imageBlurRadius)
            ZoomableContainer(
                onSingleTap: onSingleTap,
                clipsContent: true,
                onTransformChange: { zoomTransform = $0 }
            ) {
                video
                    .frame(width: metrics.videoSize?.width, height: metrics.videoSize?.height)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: metrics.videoCornerRadius * chrome.borderOpacity, style: .continuous))
            }
            .mask {
                // Rounded to match the sharp layer's own clip — a *plain* rectangle mask would cut
                // a hard square corner at the box's fixed edge regardless of what's rendered
                // underneath: past scale 1 the sharp content's own rounded corners are scaled up
                // and pushed outward by the pinch, past where this fixed-size mask cuts, so the
                // corner arc actually visible at the boundary is whichever shape *this* mask is.
                RoundedRectangle(cornerRadius: metrics.videoCornerRadius * chrome.borderOpacity, style: .continuous)
                    .frame(width: metrics.videoSize?.width, height: metrics.videoSize?.height)
            }
        }
        .overlay {
            AuroraZoomFrame(cornerRadius: metrics.videoCornerRadius, lineWidth: metrics.videoRimWidth, opacity: chrome.borderOpacity)
                .frame(width: metrics.videoSize?.width, height: metrics.videoSize?.height)
        }
        .auroraCardGlow(opacity: metrics.cardGlowOpacity * chrome.borderOpacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: arrangement.videoIgnoredEdges)
    }
}
