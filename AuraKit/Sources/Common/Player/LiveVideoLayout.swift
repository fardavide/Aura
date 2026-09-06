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

    /// The live transform `ZoomableContainer` reports, fed to `AuroraZoomBleed` for the ambient
    /// glow behind the frame. `@State`, not a local in `videoSurface`, so it survives that view's
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

    private func videoSurface(_ metrics: LiveVideoMetrics) -> some View {
        let chrome = AuroraZoomChrome(scale: zoomTransform.scale)
        return ZoomableContainer(
            onSingleTap: onSingleTap,
            clipsContent: true,
            onTransformChange: { zoomTransform = $0 }
        ) { video }
            .background(.black)
            .frame(width: metrics.videoSize?.width, height: metrics.videoSize?.height)
            .auroraFrame(cornerRadius: metrics.videoCornerRadius, lineWidth: metrics.videoRimWidth, borderOpacity: chrome.borderOpacity)
            // Behind the sized, framed card — the ambient glow a zoomed frame casts past its own
            // edge (mirrors the same shared `AVPlayer` into a second, blurred `AVPlayerLayer`;
            // `LivePlayerModel.attach` only tracks the first layer it sees, so PiP is unaffected).
            // Placed *after* `.auroraFrame`, not before: that modifier clips its content to the
            // card's rounded rect, and a bleed added before it gets clipped away to nothing along
            // with the card — verified this was exactly why the glow only ever showed on Timeline
            // detail (which draws no frame/clip at all) and never on this screen.
            .background { AuroraZoomBleed(opacity: chrome.glassOpacity, transform: zoomTransform) { video } }
            .auroraCardGlow(opacity: metrics.cardGlowOpacity * chrome.borderOpacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: arrangement.videoIgnoredEdges)
    }
}
