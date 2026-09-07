import SwiftUI

import CommonDesign

/// The live view's on-screen composition, one view tree whose two `LiveVideoArrangement`s differ
/// only in values (never a second `body` branch for layout purposes — see the type's own doc
/// comment for why): a framed 16:9 card centred on the aurora background with the controls
/// floating below it (`.card`), or the video filling the screen **behind** the safe area with the
/// transport controls overlaid **inside** it (`.fill`). Split out from `LiveVideoView` so this
/// layout can be snapshot-tested with a placeholder video and a fixed control state, without
/// constructing a real player.
///
/// `.card`'s zoomed picture grows all the way to the true screen edges — behind the nav bar and
/// behind the floating controls — the same "grow past the rest-state card, unbound" pattern
/// `RecordingDetailLayout.growableSlot`/`growingAboveThePanel` use, adapted for a canvas whose top
/// exclusion (the nav bar) isn't a view this layout owns and can measure directly, only a safe-area
/// inset. `.fill` (compact height) is already unconditionally full-bleed and untouched by any of
/// this — `videoSurface` branches by arrangement specifically so `.fill`'s working, already-shipped
/// code path stays exactly as it was.
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
    /// `.card`'s controls no longer reserve `safeAreaInset` space (so the zoomed picture can grow
    /// behind them) — this is their measured height instead, read the same way Timeline detail
    /// measures its own panel (`.onGeometryChange`, not `PreferenceKey` — see that type's own doc
    /// comment for the debug-label-verified reason). Unused by `.fill`.
    @State private var controlsHeight: CGFloat = 0

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
            // `restCanvas` excludes the controls' measured height too, on top of what `geo.size`
            // already excludes automatically (the nav bar above, the home indicator below) — the
            // same canvas `.card`'s card was always centred against, now computed explicitly
            // because controls no longer reserve it via `safeAreaInset`.
            let restCanvas = CGSize(width: geo.size.width, height: max(0, geo.size.height - controlsHeight))
            let metrics = arrangement.metrics(canvas: restCanvas)
            ZStack(alignment: .topLeading) {
                videoSurface(metrics, geo: geo, restCanvas: restCanvas)
                AuroraLivePill(style: .glass)
                    .padding(.leading, metrics.livePillInset.x)
                    .padding(.top, metrics.livePillInset.y)
                    .opacity(areControlsVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: areControlsVisible)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay(alignment: .bottom) {
            controls
                .padding(.bottom, arrangement.controlsBottomInset)
                .opacity(areControlsVisible ? 1 : 0)
                .allowsHitTesting(areControlsVisible)
                .animation(.easeInOut(duration: 0.2), value: areControlsVisible)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
        }
        .auroraBackground()
    }

    @ViewBuilder
    private func videoSurface(_ metrics: LiveVideoMetrics, geo: GeometryProxy, restCanvas: CGSize) -> some View {
        switch arrangement {
        case .fill: fillVideoSurface(metrics)
        case .card: cardVideoSurface(metrics, geo: geo, restCanvas: restCanvas)
        }
    }

    /// Unchanged from before this pass: already unconditionally full-bleed
    /// (`arrangement.videoIgnoredEdges` is `.all`), so there's no rest-state-vs-growth distinction
    /// to make here at all.
    private func fillVideoSurface(_ metrics: LiveVideoMetrics) -> some View {
        let chrome = AuroraZoomChrome(scale: zoomTransform.scale)
        return ZStack {
            video
                .frame(width: metrics.videoSize?.width, height: metrics.videoSize?.height)
                .background(.black)
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

    /// The card's border is a fixed-size, non-clipping overlay (`AuroraZoomFrame`) — it never
    /// resizes — so the picture underneath is free to grow past it, all the way to the true screen
    /// edges: `ZoomableContainer` is given an *explicit* `growthCanvas`-sized frame (not the
    /// ambient, safe-area-bounded one `.frame(maxWidth: .infinity, maxHeight: .infinity)` alone
    /// would propose) plus `.ignoresSafeArea()`, so it clips and measures against the true full
    /// screen — behind the nav bar, behind the floating controls, same idea as
    /// `RecordingDetailLayout.growingAboveThePanel`, just derived from `GeometryReader`'s own
    /// `safeAreaInsets` instead of a view this layout can measure directly, since the nav bar
    /// belongs to `NavigationStack`, not to this layout.
    ///
    /// `restOffset` keeps the rest-state card exactly where `metrics` (computed against the
    /// *smaller*, safe `restCanvas`) already puts it — centred between the nav bar and the
    /// controls, unchanged from before this pass — even though every layer here is now measured
    /// against the *bigger* `growthCanvas`. Applied via `ZoomableContainer`'s `restOffset`
    /// parameter for the interactive layer, and via a matching `.offset()` on every other
    /// rest-state-positioned piece drawn by hand: the blurred backdrop, the mask, the border rim —
    /// see `RecordingDetailLayout.growableSlot`'s identical `topInset` handling for why this must
    /// be `.offset()`, never `.padding()` on the whole surface (padding would shrink what
    /// `ZoomableContainer` measures as its own canvas, capping growth right back where it started).
    private func cardVideoSurface(_ metrics: LiveVideoMetrics, geo: GeometryProxy, restCanvas: CGSize) -> some View {
        let chrome = AuroraZoomChrome(scale: zoomTransform.scale)
        let growthCanvas = CGSize(
            width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
            height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
        )
        let restOffset = CGSize(width: 0, height: (geo.safeAreaInsets.top - controlsHeight) / 2)
        return ZStack {
            video
                .frame(width: metrics.videoSize?.width, height: metrics.videoSize?.height)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: metrics.videoCornerRadius * chrome.borderOpacity, style: .continuous))
                .scaleEffect(zoomTransform.scale)
                .offset(zoomTransform.offset)
                .offset(restOffset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .blur(radius: chrome.imageBlurRadius)
            ZoomableContainer(
                onSingleTap: onSingleTap,
                clipsContent: true,
                contentSize: metrics.videoSize,
                restOffset: restOffset,
                onTransformChange: { zoomTransform = $0 }
            ) {
                video
                    .frame(width: metrics.videoSize?.width, height: metrics.videoSize?.height)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: metrics.videoCornerRadius * chrome.borderOpacity, style: .continuous))
            }
            .mask {
                RoundedRectangle(cornerRadius: metrics.videoCornerRadius * chrome.borderOpacity, style: .continuous)
                    .frame(width: metrics.videoSize?.width, height: metrics.videoSize?.height)
                    .offset(restOffset)
            }
        }
        .overlay {
            AuroraZoomFrame(cornerRadius: metrics.videoCornerRadius, lineWidth: metrics.videoRimWidth, opacity: chrome.borderOpacity)
                .frame(width: metrics.videoSize?.width, height: metrics.videoSize?.height)
                .offset(restOffset)
        }
        .auroraCardGlow(opacity: metrics.cardGlowOpacity * chrome.borderOpacity)
        .frame(width: growthCanvas.width, height: growthCanvas.height)
        .ignoresSafeArea()
    }
}
