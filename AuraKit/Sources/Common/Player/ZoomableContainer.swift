import SwiftUI

/// Adds pinch-to-zoom, drag-to-pan and double-tap zoom toggle around viewport-filling
/// content (the live player). All gestures are attached as `simultaneousGesture` so the
/// hosted player's own recognizers (tap-to-toggle controls, PiP) keep working, and all
/// geometry goes through the clamped `ZoomTransform` math.
public struct ZoomableContainer<Content: View>: View {
    private let content: Content
    /// Fired on a single tap that is not part of a double-tap or a pan — the host uses it to
    /// toggle its overlay chrome. Kept here (not on the host) so it shares the gesture arena with
    /// the double-tap and is disambiguated against it.
    private let onSingleTap: () -> Void
    /// Whether zoomed content is cut at the container's bounds. The full-screen live view clips;
    /// the recording detail's video slot doesn't, so zoomed footage spills under the glass panel
    /// beside it instead of stopping dead at an invisible line.
    private let clipsContent: Bool
    /// Where unscaled content sits within a container larger than its own rest-state size — the
    /// growing-past-the-frame screens all offer a bigger canvas than the small card they draw at
    /// rest. Defaults to `.center` (Live's card); Timeline detail's top-anchored slot passes `.top`.
    private let alignment: Alignment
    /// The rest-state size of `content` at scale 1 — `nil` means content fills the container
    /// exactly (Live's `.fill`, Timeline detail's `.rail`, today's behavior). `ZoomTransform`'s
    /// whole model treats its own `viewport:` parameter as the content's rest size (see that type's
    /// doc comment), so a caller whose content is *smaller* than the container — every
    /// growing-past-the-frame screen — must supply this, or every anchor/pan/clamp computes
    /// relative to the container's much bigger size instead: a pinch anywhere on a small, off-centre
    /// box then reads as a `UnitPoint` near the *box's own position* within the big canvas — close
    /// to 0 for a `.top`-aligned box (the zoom appears to only grow downward, since a pinch anywhere
    /// on the box computes an anchor far above the box's own centre), always near 0.5 for a
    /// `.center`-aligned one (the zoom always anchors near-centre, however precisely you pinch,
    /// since the whole box occupies only a small central sliver of the big canvas) — never where
    /// within the box the user actually pinched. Reported directly, against both screens at once:
    /// Timeline detail's zoom "only growing downward", Live's card "zooming from center only,
    /// needing a pan after".
    private let contentSize: CGSize?
    /// A fixed, gesture-independent visual shift applied *after* the zoom transform — for a caller
    /// whose rest-state card sits away from `alignment`'s own edge (Timeline detail centers its
    /// card in the gap above a variable-height panel, not flush to the container's own top). Unlike
    /// padding the whole container, this doesn't shrink `proxy.size` — the canvas the gesture math
    /// and the growth boundary both measure — it only shifts what's painted; hit-testing and the
    /// zoom clamp still cover the container's full, true bounds. Defaults to `.zero` (Live's card,
    /// and any caller with nothing to correct for).
    private let restOffset: CGSize
    /// Reports the transform actually on screen — the committed one with any in-flight gesture
    /// folded in, the same value `displayedTransform` renders — on every change, including live
    /// updates mid-pinch. The container owns its zoom math and stays self-contained; a caller that
    /// wants to react to it (`AuroraZoomBleed`, an ambient blur behind the frame) reads it here
    /// rather than duplicating gesture state.
    private let onTransformChange: (ZoomTransform) -> Void

    @State private var transform = ZoomTransform.standard()
    /// In-flight gesture deltas, applied on top of `transform` for display and folded into it in
    /// each gesture's `onEnded`. `@GestureState` (not plain `@State`) is load-bearing: a system
    /// gesture that out-competes ours for the touch — the navigation interactive-pop swipe-back,
    /// most often — *cancels* rather than ends it, so `onEnded` never runs. `@GestureState` still
    /// resets to `nil` on cancellation; a plain flag/base pair set in `onChanged` and only cleared
    /// in `onEnded` would stay stuck permanently "mid-gesture", wedging every future pinch and pan
    /// against a gesture that never actually finished (see `ScrollableTimelineView.magnify` for the
    /// same failure mode, already fixed there the same way).
    @GestureState private var magnifyPhase: MagnifyPhase?
    @GestureState private var panTranslation: CGSize?

    private struct MagnifyPhase {
        let magnification: CGFloat
        let anchor: UnitPoint
    }

    public init(
        onSingleTap: @escaping () -> Void,
        clipsContent: Bool,
        alignment: Alignment = .center,
        contentSize: CGSize? = nil,
        restOffset: CGSize = .zero,
        onTransformChange: @escaping (ZoomTransform) -> Void = { _ in },
        @ViewBuilder content: () -> Content
    ) {
        self.onSingleTap = onSingleTap
        self.clipsContent = clipsContent
        self.alignment = alignment
        self.contentSize = contentSize
        self.restOffset = restOffset
        self.onTransformChange = onTransformChange
        self.content = content()
    }

    @ViewBuilder public var body: some View {
        if clipsContent {
            zoomArea.clipped()
        } else {
            zoomArea
        }
    }

    private var zoomArea: some View {
        GeometryReader { proxy in
            let displayed = displayedTransform(in: proxy.size)
            ZStack(alignment: alignment) {
                content
                    .scaleEffect(displayed.scale)
                    .offset(displayed.offset)
            }
            .offset(restOffset)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .simultaneousGesture(magnify(in: proxy.size))
            .simultaneousGesture(pan(in: proxy.size))
            .simultaneousGesture(taps(in: proxy.size))
            .accessibilityActions {
                if transform.isZoomed {
                    Button("Reset Zoom") {
                        withAnimation(.snappy) { transform = transform.reset() }
                    }
                }
            }
            .onChange(of: proxy.size) { _, newArena in
                transform = transform.panned(by: .zero, viewport: contentSize ?? newArena)
            }
            .onChange(of: displayed, initial: true) { _, new in onTransformChange(new) }
        }
    }

    /// `transform` (the last *committed* gesture) with any gesture still in flight applied on top,
    /// in the same order a commit would fold it in — see the type's gesture-state doc comment.
    private func displayedTransform(in arena: CGSize) -> ZoomTransform {
        let viewport = contentSize ?? arena
        var result = transform
        if let magnifyPhase {
            result = result.magnified(by: magnifyPhase.magnification, anchor: magnifyPhase.anchor, viewport: viewport)
        }
        if let panTranslation {
            result = result.panned(by: panTranslation, viewport: viewport)
        }
        return result
    }

    /// Where `content`, at its rest size, sits within `arena` (the container's full, measured
    /// size) — every gesture anchor is computed relative to this, not to `arena` directly, so a
    /// pinch lands on the point of the *content* the user is actually touching. `.zero`-origin,
    /// `arena`-sized when `contentSize` is `nil`: content fills the container, so it *is* the arena
    /// (today's `.fill`/`.rail` behavior, unchanged). Only `.center` and `.top` are supported,
    /// matching every caller today — both centre horizontally, so only the vertical origin depends
    /// on which.
    func contentRect(in arena: CGSize) -> CGRect {
        guard let contentSize else { return CGRect(origin: .zero, size: arena) }
        let x = (arena.width - contentSize.width) / 2 + restOffset.width
        let y = (alignment == .top ? 0 : (arena.height - contentSize.height) / 2) + restOffset.height
        return CGRect(origin: CGPoint(x: x, y: y), size: contentSize)
    }

    private func anchor(at location: CGPoint, in arena: CGSize) -> UnitPoint? {
        let rect = contentRect(in: arena)
        guard rect.width > 0, rect.height > 0 else { return nil }
        return UnitPoint(x: (location.x - rect.minX) / rect.width, y: (location.y - rect.minY) / rect.height)
    }

    private func magnify(in arena: CGSize) -> some Gesture {
        MagnifyGesture()
            .updating($magnifyPhase) { value, phase, _ in
                // `MagnifyGesture.Value.startAnchor` reports `.center` in practice, which
                // pins every pinch to the middle of the content. Derive the anchor from the
                // pinch-midpoint location instead — same approach the double-tap uses.
                guard let anchor = anchor(at: value.startLocation, in: arena) else { return }
                phase = MagnifyPhase(magnification: value.magnification, anchor: anchor)
            }
            .onEnded { value in
                guard let anchor = anchor(at: value.startLocation, in: arena) else { return }
                transform = transform.magnified(by: value.magnification, anchor: anchor, viewport: contentSize ?? arena)
            }
    }

    private func pan(in arena: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($panTranslation) { value, translation, _ in
                // At 1x the drag stays inert so it never fights navigation swipe-back.
                guard transform.isZoomed else { return }
                translation = value.translation
            }
            .onEnded { value in
                guard transform.isZoomed else { return }
                transform = transform.panned(by: value.translation, viewport: contentSize ?? arena)
            }
    }

    /// Double-tap toggles zoom at the tap point; a lone single tap forwards to `onSingleTap`.
    /// `exclusively(before:)` gives the double-tap priority, so SwiftUI holds the single tap until
    /// it's sure a second tap isn't coming — the single fires only when the double fails.
    private func taps(in arena: CGSize) -> some Gesture {
        let doubleTap = SpatialTapGesture(count: 2)
            .onEnded { value in
                guard let anchor = anchor(at: value.location, in: arena) else { return }
                withAnimation(.snappy) {
                    transform = transform.togglingZoom(at: anchor, viewport: contentSize ?? arena)
                }
            }
        let singleTap = SpatialTapGesture(count: 1)
            .onEnded { _ in onSingleTap() }
        return doubleTap.exclusively(before: singleTap)
    }
}
