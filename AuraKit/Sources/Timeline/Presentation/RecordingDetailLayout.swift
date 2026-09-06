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
/// The video is pinch-zoomable everywhere. On the phones its **slot** is unclipped, so zoomed
/// footage overflows it and slides under the glass instead of stopping at an invisible line; the
/// iPad hero clips to its frame, since nothing overlaps it. The chrome and the panel live outside
/// the zoom and never scale. The slot itself is full-bleed everywhere — no rim, no corner radius,
/// no inset (the mock's only framed video is the Live screen's, not this one).
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

    private static var railWidth: CGFloat { 168 }
    private static var splitPanelMaxWidth: CGFloat { 1_100 }

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
            slot(clipped: false)
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
            slot(clipped: false)
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
            slot(clipped: true)
                .background(Color.auroraBase)
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
    /// The letterbox colour sits in two different places depending on `clipped`: unclipped
    /// (stacked/rail), it rides *inside* the zoom with the video, since the container has no fixed
    /// boundary to paint behind; clipped (split), the caller paints it *outside*, fixed behind the
    /// container's own bounds, so it doesn't pan or scale with a pinch the way the picture does.
    private func slot(clipped: Bool) -> some View {
        ZoomableContainer(onSingleTap: {}, clipsContent: clipped) {
            if clipped { video } else { video.background(Color.auroraBase) }
        }
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
