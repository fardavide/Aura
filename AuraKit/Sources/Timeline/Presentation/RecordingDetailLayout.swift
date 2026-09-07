import SwiftUI

import CommonDesign
import CommonPlayer

/// The Timeline-detail screen's on-screen composition: one camera's footage with the timeline panel
/// against it, in the arrangement the available space calls for.
///
/// - **Phone upright** — the footage sits centred in the gap between the nav bar and the panel at
///   rest, same as Live's own card; zoomed in, the picture grows past that rest-state card, past
///   the panel's own space too, all the way to the screen edge, with the panel floating on top —
///   same as `.split`.
/// - **Phone on its side** — the footage takes the space beside a tall rail down the trailing
///   edge; the same rule, sideways, but this one doesn't grow past its own box yet (see `rail`'s
///   doc comment).
/// - **iPad and Mac** — a 16:9 hero centred above the panel at rest; zoomed in, same
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
    /// The timeline panel's actual rendered height, measured via `.onGeometryChange` — see
    /// `growingAboveThePanel`'s doc comment for why.
    @State private var panelHeight: CGFloat = 0

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

    /// `boxSize` is the 16:9 card `.aspectRatio(16/9, .fit)` would have produced against the full
    /// `canvas` width, computed by hand because `growableSlot` needs it explicitly (see that
    /// function's doc comment for why) — capped by `availableHeight` too (same technique as
    /// `LiveVideoArrangement.metrics(canvas:)`'s own `min(canvas.width - 32, canvas.height * 16/9)`),
    /// not just width, so the box can never be intrinsically taller than the space actually left
    /// above the panel — a wide-but-short canvas otherwise produces a box that overlaps the panel
    /// no matter how the *centering* math is done, since there's nowhere non-overlapping to center
    /// it into.
    private func stacked(insets: EdgeInsets, canvas: CGSize) -> some View {
        let availableHeight = max(0, canvas.height - panelHeight)
        let boxWidth = min(canvas.width, availableHeight * 16 / 9)
        let boxSize = CGSize(width: boxWidth, height: boxWidth * 9 / 16)
        return growingAboveThePanel(boxSize: boxSize, canvas: canvas, panelInsetBottom: insets.bottom, panelArrangement: .stacked)
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
        // Also capped by `availableHeight` — see `stacked`'s identical reasoning; a wide, short
        // iPad-landscape canvas is exactly the case where a width-only cap produces a box taller
        // than the space actually free above the panel.
        let availableHeight = max(0, canvas.height - panelHeight)
        let boxWidth = min(canvas.width - 40, Self.splitPanelMaxWidth, availableHeight * 16 / 9)
        let boxSize = CGSize(width: boxWidth, height: boxWidth * 9 / 16)
        return growingAboveThePanel(boxSize: boxSize, canvas: canvas, panelInsetBottom: insets.bottom, panelArrangement: .split)
            .auroraBackground()
            .ignoresSafeArea(.container, edges: .bottom)
            .overlay { surfaceHighlight }
    }

    /// `.stacked` and `.split`'s shared composition: the video sits centred in the gap between the
    /// top of `canvas` (the nav bar's bottom edge — see `body`'s doc comment) and the panel, at
    /// rest, but is free to grow past *both* boundaries when zoomed, all the way to filling
    /// `canvas` — the panel floats on top of it rather than sharing space with it, so the two need
    /// different reference frames: growth uses the *full* `canvas` (via `growableSlot` getting no
    /// explicit frame of its own, same as `LiveVideoLayout`), while the rest-state position needs
    /// the panel's actual rendered height, which is content-driven and not known in advance.
    ///
    /// That height is read via `.onGeometryChange` into `panelHeight` (`@State`, not a local —
    /// the same reason `zoomTransform` is) — the same pattern `CameraGridView` already uses for
    /// `headerHeight`. Two other approaches were tried and dropped first, both confirmed wrong by
    /// a debug label rendering the live values, not just reasoned about:
    /// - `PreferenceKey` + `.onPreferenceChange` compiled and looked plausible, but the debug label
    ///   showed `panelHeight` permanently stuck at its `0` default — the change handler never fired
    ///   in this view tree (a `GeometryReader` reporting through `.preference` from inside the
    ///   panel's own `.background`, several containers deep, apparently isn't enough on its own;
    ///   `.onGeometryChange` attached directly to the measured view has no such gap).
    /// - `PreferenceKey` + `backgroundPreferenceValue` would have read the value within the same
    ///   layout pass (no settle at all) had it worked, but building the video as a `.background` of
    ///   a bare `ZStack { panel }` surfaced a worse, unrelated problem first: a bare `ZStack`
    ///   proposes its own (canvas-sized) size to *every* child uniformly, and
    ///   `RecordingTimelinePanel`'s content has enough internal flexibility to visibly grow into
    ///   that oversized proposal, swallowing the whole canvas and hiding the video entirely.
    ///   Avoiding that needs the panel back in its own `VStack` + leading `Spacer` (which measures
    ///   the panel at its intrinsic height first, per `growingAboveThePanel` itself), which doesn't
    ///   compose with `backgroundPreferenceValue`'s own structure.
    ///
    /// `.onGeometryChange` still settles a render after the panel first appears — the same
    /// one-frame-late class of issue `body`'s own doc comment flags for safe-area insets — but in
    /// practice this is a purely cosmetic settle (a card's rest position, not a value the user is
    /// watching move), and the screen is already mid-navigation-push-transition when it first
    /// appears, which masks it.
    private func growingAboveThePanel(
        boxSize: CGSize,
        canvas: CGSize,
        panelInsetBottom: CGFloat,
        panelArrangement: RecordingTimelinePanel.Arrangement
    ) -> some View {
        let availableHeight = max(0, canvas.height - panelHeight)
        let topInset = max(0, (availableHeight - boxSize.height) / 2)
        // The panel sits in its own `VStack` with a leading `Spacer`, not directly in the outer
        // `ZStack` — a bare `ZStack` proposes its own (canvas-sized) size to *every* child
        // uniformly, and `RecordingTimelinePanel`'s content has enough internal flexibility to
        // actually grow into that oversized proposal (confirmed: it visibly expanded to swallow
        // the whole canvas, hiding the video entirely, before this was caught and fixed). A
        // `VStack` measures the panel at its own intrinsic height first and hands only the
        // *leftover* space to the `Spacer` — the same reason the original, pre-growth `VStack`
        // layout never had this problem.
        return ZStack {
            growableSlot(boxSize: boxSize, alignment: .top, topInset: topInset)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                panel(panelArrangement)
                    .padding(.bottom, panelInsetBottom)
                    .auroraSheet(edge: .bottom, showsGrabber: false)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    /// scaled, blurred backdrop; both are exactly the same size here (box == canvas, no growth),
    /// and *both* are clipped to the same rounded rect, so the opaque sharp layer fully covers the
    /// backdrop everywhere and no blur ever shows — correct, since there's no "outside the box"
    /// region on this arrangement for it to read as. The backdrop's own rounding still matters even
    /// though it's fully covered at rest: without it, its square corners peek out from behind the
    /// sharp layer's rounded ones right at the 4 corners, where the two shapes actually differ.
    private func slot() -> some View {
        let chrome = AuroraZoomChrome(scale: zoomTransform.scale)
        return ZStack {
            video
                .background(Color.auroraBase)
                // Rounded to match the sharp layer's own clip: the sharp layer is clipped to a
                // rounded rect, not a plain rectangle, so it doesn't actually cover this backdrop's
                // 4 corners even though the two are otherwise the same size — an unrounded backdrop
                // peeks out from behind the rounded sharp layer right there.
                .clipShape(RoundedRectangle(cornerRadius: Self.videoCornerRadius * chrome.borderOpacity, style: .continuous))
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
    /// that larger canvas (`.top`, for both callers — `growingAboveThePanel` centers the card
    /// above the panel via `topInset`, a *visual* shift, not by changing this alignment; see
    /// `LiveVideoLayout.videoSurface` for the `.center` version of the same underlying pattern).
    ///
    /// `topInset` must be applied as a rendering-only shift on each piece individually (`.offset`
    /// on the two video layers, matching `ZoomableContainer`'s own `restOffset`; `.offset` on the
    /// mask and the fixed overlays), never as `.padding` on this whole function's *return value* —
    /// that was the previous, wrong approach, and it silently broke growth: padding this view
    /// shrinks what it reports as its own size to its parent, which is exactly the size
    /// `ZoomableContainer`'s internal `GeometryReader` reads as the canvas to grow into and clip
    /// against — so the growable area was quietly `topInset` points shorter than the true canvas,
    /// unable to reach the actual top edge no matter how far zoomed. Reported directly: "the image
    /// is bounded to do not exceed the top bound."
    ///
    /// The blur only ever shows in the picture that's grown *past* the card's rest-state rect, not
    /// the whole picture: a non-interactive mirror of the same content, scaled and panned
    /// identically, sits behind it blurred and canvas-filling; the real, sharp, gesture-driving
    /// `ZoomableContainer` sits in front, masked down to just the card's own rect at `alignment`,
    /// so the sharp copy is all that shows there and the blurred mirror only shows through where
    /// the picture has grown beyond it.
    private func growableSlot(boxSize: CGSize, alignment: Alignment, topInset: CGFloat = 0) -> some View {
        let chrome = AuroraZoomChrome(scale: zoomTransform.scale)
        return ZStack(alignment: alignment) {
            video
                .frame(width: boxSize.width, height: boxSize.height)
                .background(Color.auroraBase)
                // Rounded to match the sharp layer's own clip and its mask — otherwise the
                // blurred backdrop's square corners peek past the border's rounded ones.
                .clipShape(RoundedRectangle(cornerRadius: Self.videoCornerRadius * chrome.borderOpacity, style: .continuous))
                .scaleEffect(zoomTransform.scale)
                .offset(zoomTransform.offset)
                .offset(y: topInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                .clipped()
                .blur(radius: chrome.imageBlurRadius)
            ZoomableContainer(
                onSingleTap: {},
                clipsContent: true,
                alignment: alignment,
                contentSize: boxSize,
                restOffset: CGSize(width: 0, height: topInset),
                onTransformChange: { zoomTransform = $0 }
            ) {
                video
                    .frame(width: boxSize.width, height: boxSize.height)
                    .background(Color.auroraBase)
                    .clipShape(RoundedRectangle(cornerRadius: Self.videoCornerRadius * chrome.borderOpacity, style: .continuous))
            }
            .mask(alignment: alignment) {
                // Rounded to match the sharp layer's own clip — see `LiveVideoLayout.videoSurface`'s
                // identical mask for why a plain rectangle here would cut a hard square corner at
                // the box's fixed edge once the scaled content's own rounding moves past it.
                RoundedRectangle(cornerRadius: Self.videoCornerRadius * chrome.borderOpacity, style: .continuous)
                    .frame(width: boxSize.width, height: boxSize.height)
                    .offset(y: topInset)
            }
        }
        .overlay(alignment: alignment) {
            AuroraZoomFrame(cornerRadius: Self.videoCornerRadius, lineWidth: Self.videoRimWidth, opacity: chrome.borderOpacity)
                .frame(width: boxSize.width, height: boxSize.height)
                .offset(y: topInset)
        }
        .auroraCardGlow(opacity: chrome.borderOpacity)
        .overlay(alignment: alignment) {
            RecordingHeroOverlay(state: state)
                .frame(width: boxSize.width, height: boxSize.height)
                .offset(y: topInset)
        }
        .overlay(alignment: alignment) {
            slotHighlight
                .frame(width: boxSize.width, height: boxSize.height)
                .offset(y: topInset)
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
