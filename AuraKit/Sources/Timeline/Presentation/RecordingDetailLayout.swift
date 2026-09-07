import SwiftUI

import CommonDesign
import CommonPlayer

/// The Timeline-detail screen's on-screen composition: one camera's footage with the timeline panel
/// against it, in the arrangement the available space calls for.
///
/// - **Phone upright** — the footage sits at the top, in the space the bottom glass panel leaves
///   free at rest, so the controls never cover the resting picture; zoomed in, the picture grows
///   past that rest-state card and the panel floats on top of it, same as `.split`.
/// - **Phone on its side** — the footage takes the space beside a tall rail down the trailing
///   edge; the same rule, sideways, but this one doesn't grow past its own box yet (see `rail`'s
///   doc comment).
/// - **iPad and Mac** — a 16:9 hero with the panel spread wide beneath it at rest; zoomed in, same
///   growth-behind-the-panel treatment as phone-upright.
///
/// The video is pinch-zoomable everywhere. At rest every arrangement's video sits in a
/// gradient-rimmed card matching the Live screen; `AuroraZoomChrome` fades that border out and
/// blurs the picture as a pinch begins, then clears the blur back to sharp as it approaches filling
/// the available canvas — one curve, shared with Live, so all three player screens read the same
/// way at any zoom level. `.stacked`/`.split` let the picture grow past its own rest-state card,
/// unbound, all the way to the screen's edge, exactly like Live (`growableSlot`); `.rail` still
/// clips hard at its own box, which is both the rest-state card and the outer growth boundary
/// there (`slot`). The chrome and the panel live outside the zoom and never scale.
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

    /// The live transform `ZoomableContainer` reports, fed to `AuroraZoomChrome` — see
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
            arrangedContent(insets: proxy.safeAreaInsets, canvas: proxy.size)
        }
    }

    @ViewBuilder
    private func arrangedContent(insets: EdgeInsets, canvas: CGSize) -> some View {
        switch arrangement {
        case .stacked: stacked(insets: insets, canvas: canvas)
        case .rail: rail(insets: insets)
        case .split: split(insets: insets, canvas: canvas)
        }
    }

    /// The picture grows past its rest-state card here, all the way to filling the screen behind
    /// the panel — matching Live — since the panel now overlays the video instead of sharing space
    /// with it in a `VStack`. `boxSize` is the 16:9 card `.aspectRatio(16/9, .fit)` would have
    /// produced against the full `canvas` width, computed by hand because `growableSlot` needs it
    /// explicitly (see that function's doc comment for why).
    private func stacked(insets: EdgeInsets, canvas: CGSize) -> some View {
        let boxSize = CGSize(width: canvas.width, height: canvas.width * 9 / 16)
        return ZStack {
            growableSlot(boxSize: boxSize, alignment: .top)
                .padding(.top, 8)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                panel(.stacked)
                    .padding(.bottom, insets.bottom)
                    .auroraSheet(edge: .bottom, showsGrabber: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .auroraBackground()
        .ignoresSafeArea(.container, edges: .bottom)
        .overlay { surfaceHighlight }
    }

    /// Unchanged from before: the picture's own aspect-fit bounds stay both the rest-state card
    /// and the outer growth boundary here — a landscape phone's rail sits beside the video rather
    /// than overlaying it, and the box is leading-anchored (not centered) within its row, which
    /// `ZoomTransform`'s pan/zoom math (documented to assume content fills its own viewport) has
    /// not been checked against; growing this one past its box is a follow-up, not this pass.
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

    private func split(insets: EdgeInsets, canvas: CGSize) -> some View {
        // The horizontal padding is reserved from the canvas *before* the max-width cap applies —
        // `min(canvas.width, cap) - 40` is wrong when `canvas.width - 40` already undercuts `cap`.
        let boxWidth = min(canvas.width - 40, Self.splitPanelMaxWidth)
        let boxSize = CGSize(width: boxWidth, height: boxWidth * 9 / 16)
        return ZStack {
            growableSlot(boxSize: boxSize, alignment: .top)
                .padding(.top, 20)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                panel(.split)
                    .padding(.bottom, insets.bottom)
                    .auroraSheet(edge: .bottom, showsGrabber: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .auroraBackground()
        .ignoresSafeArea(.container, edges: .bottom)
        .overlay { surfaceHighlight }
    }

    /// The rail's zoomable video area — the video's own aspect-fit bounds are both the rest-state
    /// card and the outer growth boundary here (see `rail`'s own doc comment for why this one
    /// doesn't grow past its box the way `growableSlot` does). At rest the video letterboxes
    /// inside this slot — the one part of the screen the panel never covers. The chrome overlays
    /// the slot *outside* the zoom, so the badges stay put and legible while the picture scales
    /// under them. The letterbox colour is painted *outside* the zoom, fixed behind the
    /// container's own bounds, so it never pans or scales with a pinch the way the picture does.
    ///
    /// The sharp, gesture-driving `ZoomableContainer` sits directly on top of an identically
    /// scaled, blurred backdrop; since both are exactly the same size here (box == canvas, no
    /// growth), the opaque sharp layer always fully covers the backdrop and no blur ever shows —
    /// correct, since there's no "outside the box" region on this arrangement for it to read as.
    private func slot() -> some View {
        let chrome = AuroraZoomChrome(scale: zoomTransform.scale)
        return ZStack {
            video
                .background(Color.auroraBase)
                .scaleEffect(zoomTransform.scale)
                .offset(zoomTransform.offset)
                .blur(radius: chrome.imageBlurRadius)
            ZoomableContainer(
                onSingleTap: {},
                clipsContent: true,
                onTransformChange: { zoomTransform = $0 }
            ) {
                video
                    .background(Color.auroraBase)
                    .clipShape(RoundedRectangle(cornerRadius: Self.videoCornerRadius * chrome.borderOpacity, style: .continuous))
            }
        }
        .overlay {
            AuroraZoomFrame(cornerRadius: Self.videoCornerRadius, lineWidth: Self.videoRimWidth, opacity: chrome.borderOpacity)
        }
        .auroraCardGlow(opacity: chrome.borderOpacity)
        .overlay { RecordingHeroOverlay(state: state) }
        .overlay { slotHighlight }
    }

    /// `stacked` and `split`'s zoomable video area: the picture grows past its own rest-state
    /// card, unbound, all the way to filling the caller's full canvas — matching Live. `boxSize`
    /// is the rest-state card's own size; the caller must offer a canvas *larger* than it (via
    /// `.frame(maxWidth: .infinity, maxHeight: .infinity)` somewhere above this in the view tree)
    /// for there to be anything to grow into, and `alignment` says where the card sits within
    /// that larger canvas at rest (`.top`, for both callers, so the footage stays at the top of
    /// the space the panel leaves free — see `LiveVideoLayout.videoSurface` for the `.center`
    /// version of the same pattern).
    ///
    /// The blur only ever shows in the picture that's grown *past* the card's rest-state rect, not
    /// the whole picture: a non-interactive mirror of the same content, scaled and panned
    /// identically, sits behind it blurred and canvas-filling; the real, sharp, gesture-driving
    /// `ZoomableContainer` sits in front, masked down to just the card's own rect at `alignment`,
    /// so the sharp copy is all that shows there and the blurred mirror only shows through where
    /// the picture has grown beyond it.
    private func growableSlot(boxSize: CGSize, alignment: Alignment) -> some View {
        let chrome = AuroraZoomChrome(scale: zoomTransform.scale)
        return ZStack(alignment: alignment) {
            video
                .frame(width: boxSize.width, height: boxSize.height)
                .background(Color.auroraBase)
                .scaleEffect(zoomTransform.scale)
                .offset(zoomTransform.offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                .clipped()
                .blur(radius: chrome.imageBlurRadius)
            ZoomableContainer(
                onSingleTap: {},
                clipsContent: true,
                alignment: alignment,
                onTransformChange: { zoomTransform = $0 }
            ) {
                video
                    .frame(width: boxSize.width, height: boxSize.height)
                    .background(Color.auroraBase)
                    .clipShape(RoundedRectangle(cornerRadius: Self.videoCornerRadius * chrome.borderOpacity, style: .continuous))
            }
            .mask(alignment: alignment) {
                Rectangle().frame(width: boxSize.width, height: boxSize.height)
            }
        }
        .overlay(alignment: alignment) {
            AuroraZoomFrame(cornerRadius: Self.videoCornerRadius, lineWidth: Self.videoRimWidth, opacity: chrome.borderOpacity)
                .frame(width: boxSize.width, height: boxSize.height)
        }
        .auroraCardGlow(opacity: chrome.borderOpacity)
        .overlay(alignment: alignment) {
            RecordingHeroOverlay(state: state)
                .frame(width: boxSize.width, height: boxSize.height)
        }
        .overlay(alignment: alignment) {
            slotHighlight
                .frame(width: boxSize.width, height: boxSize.height)
        }
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
