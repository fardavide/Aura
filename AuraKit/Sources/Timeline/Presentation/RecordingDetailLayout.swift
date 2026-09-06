import SwiftUI

import CommonDesign
import CommonPlayer

/// The Timeline-detail screen's on-screen composition: one camera's footage with the timeline panel
/// against it, in the arrangement the available space calls for.
///
/// - **Phone upright** — the footage sits at the top, in the space the bottom glass panel leaves
///   free, so the controls never cover the resting picture.
/// - **Phone on its side** — the footage takes the space beside a tall rail down the trailing
///   edge; the same rule, sideways.
/// - **iPad and Mac** — a 16:9 hero with the panel spread wide beneath it, the time axis and the
///   controls side by side.
///
/// The video is pinch-zoomable everywhere and clips consistently to its **slot** — zoomed footage
/// never overflows into the panel or under the glass. At rest the slot carries the same
/// gradient-rimmed card frame as the Live screen; `AuroraZoomChrome` fades that border and fades in
/// an `AuroraZoomBleed` behind it as a pinch progresses, then fades both to nothing as the picture
/// approaches filling the slot — one curve, shared with Live, so all three player screens read the
/// same way at any zoom level. The chrome and the panel live outside the zoom and never scale.
///
/// Split out from `RecordingPlayerView` so every arrangement can be screenshot-tested over a
/// placeholder, with literal state and no player — and with `cameraAreaHighlights` on, the
/// baselines outline the surface and the slot so a panel creeping over the picture is caught here.
public struct RecordingDetailLayout<Video: View>: View {
    private let state: RecordingDetailState
    private let actions: RecordingDetailActions
    private let filmstrip: RecordingFilmstripStore
    private let video: Video

    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.cameraAreaHighlights) private var cameraAreaHighlights

    /// The live transform `ZoomableContainer` reports, fed to `AuroraZoomBleed` — see
    /// `LiveVideoLayout`'s identical property for why this is `@State`, not a local in `slot()`.
    @State private var zoomTransform = ZoomTransform.standard()

    private static var railWidth: CGFloat { 168 }
    private static var splitPanelMaxWidth: CGFloat { 1_100 }
    /// Matches `LiveVideoArrangement.card`'s frame exactly, so the resting picture reads the same
    /// on both screens.
    private static var videoCornerRadius: CGFloat { 22 }
    private static var videoRimWidth: CGFloat { 1.5 }

    public init(
        state: RecordingDetailState,
        actions: RecordingDetailActions,
        filmstrip: RecordingFilmstripStore,
        @ViewBuilder video: () -> Video
    ) {
        self.state = state
        self.actions = actions
        self.filmstrip = filmstrip
        self.video = video()
    }

    public var body: some View {
        // A `GeometryReader` reads the real safe-area insets in one layout pass — a `@State`
        // measurement settles a pass later, which would leave the panel content misjudging the
        // indicator's height for one frame (0.5.2 snapshot-determinism rule).
        GeometryReader { proxy in
            arrangedContent(insets: proxy.safeAreaInsets)
        }
    }

    @ViewBuilder
    private func arrangedContent(insets: EdgeInsets) -> some View {
        switch arrangement {
        case .stacked: stacked(insets: insets)
        case .rail: rail(insets: insets)
        case .split: split(insets: insets)
        }
    }

    private func stacked(insets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            slot()
                .aspectRatio(16 / 9, contentMode: .fit)
                .padding(.top, 8)
            Spacer(minLength: 12)
            panel(.stacked)
                .padding(.bottom, insets.bottom)
                .auroraSheet(edge: .bottom, showsGrabber: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .auroraBackground()
        .ignoresSafeArea(.container, edges: .bottom)
        .overlay { surfaceHighlight }
    }

    private func rail(insets: EdgeInsets) -> some View {
        HStack(spacing: 10) {
            slot()
                .aspectRatio(16 / 9, contentMode: .fit)
                .padding(.leading, 10)
                .padding(.vertical, 10)
            panel(.rail)
                .frame(width: Self.railWidth)
                .padding(.trailing, insets.trailing)
                .padding(.bottom, insets.bottom)
                .auroraSheet(edge: .trailing, showsGrabber: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .auroraBackground()
        // Both ignored edges carry content (the rail and, inside it, the new Live pill row), so
        // both are paid back above — a single blanket `[.bottom, .trailing]` here with only the
        // trailing edge repaid is exactly how the rail's last row ends up under the indicator.
        .ignoresSafeArea(.container, edges: [.trailing, .bottom])
        .overlay { surfaceHighlight }
    }

    private func split(insets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            slot()
                .aspectRatio(16 / 9, contentMode: .fit)
                // Absorbs the free height instead of a trailing `Spacer` — with a content-height
                // sheet under a fixed-height slot, an 11" iPad portrait would otherwise open a
                // ≈370pt void between the two.
                .frame(maxWidth: Self.splitPanelMaxWidth)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .overlay { surfaceHighlight }
            panel(.split)
                .padding(.bottom, insets.bottom)
                .auroraSheet(edge: .bottom, showsGrabber: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .auroraBackground()
        .ignoresSafeArea(.container, edges: .bottom)
    }

    /// The zoomable video area. At rest the video letterboxes inside this slot — the one part of
    /// the screen the panel never covers. The chrome overlays the slot *outside* the zoom, so the
    /// badges stay put and legible while the picture scales under them.
    ///
    /// The letterbox colour is painted *outside* the zoom, fixed behind the container's own
    /// bounds, so it never pans or scales with a pinch the way the picture does — consistent
    /// across every arrangement now that every arrangement clips.
    private func slot() -> some View {
        let chrome = AuroraZoomChrome(scale: zoomTransform.scale)
        return ZoomableContainer(
            onSingleTap: {},
            clipsContent: true,
            onTransformChange: { zoomTransform = $0 }
        ) { video }
            .background(Color.auroraBase)
            .auroraFrame(cornerRadius: Self.videoCornerRadius, lineWidth: Self.videoRimWidth, borderOpacity: chrome.borderOpacity)
            // Same ordering rule as `LiveVideoLayout.videoSurface` — the bleed sits behind the
            // frame's own clip, not in front of it, or the frame silently cuts the glow down to
            // its own bounds and it never shows.
            .background { AuroraZoomBleed(opacity: chrome.glassOpacity, transform: zoomTransform) { video } }
            .auroraCardGlow(opacity: chrome.borderOpacity)
            .overlay { RecordingHeroOverlay(state: state) }
            .overlay { slotHighlight }
    }

    private func panel(_ arrangement: RecordingTimelinePanel.Arrangement) -> some View {
        RecordingTimelinePanel(arrangement: arrangement, state: state, actions: actions, filmstrip: filmstrip)
    }

    /// Diagnostics for the screenshot suite: everything zoomed footage may cover. Drawn above the
    /// panel on purpose — the surface legitimately runs under it.
    @ViewBuilder private var surfaceHighlight: some View {
        if cameraAreaHighlights {
            areaHighlight(CameraAreaHighlights.surface, label: "SURFACE", labelAt: .bottomTrailing)
        }
    }

    /// Diagnostics for the screenshot suite: the resting video's space. Any glass over this
    /// outline in a baseline is a layout regression.
    @ViewBuilder private var slotHighlight: some View {
        if cameraAreaHighlights {
            areaHighlight(CameraAreaHighlights.slot, label: "CAMERA SLOT", labelAt: .bottomLeading)
        }
    }

    private func areaHighlight(_ color: Color, label: String, labelAt alignment: Alignment) -> some View {
        Rectangle()
            .fill(color.opacity(0.08))
            .overlay {
                Rectangle().strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
            .overlay(alignment: alignment) {
                Text(label)
                    .auroraText(.overline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.85), in: Capsule())
                    .padding(10)
                    .fixedSize()
            }
            .allowsHitTesting(false)
    }

    /// Wide and short is a phone on its side — iPad reports a regular height in every orientation
    /// and multitasking mode, and macOS has no size class at all, so both take the split.
    private var arrangement: RecordingTimelinePanel.Arrangement {
        #if os(iOS)
        if verticalSizeClass == .compact { return .rail }
        return horizontalSizeClass == .compact ? .stacked : .split
        #else
        return .split
        #endif
    }
}
