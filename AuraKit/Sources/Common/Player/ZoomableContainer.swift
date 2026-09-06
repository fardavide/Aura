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
        @ViewBuilder content: () -> Content
    ) {
        self.onSingleTap = onSingleTap
        self.clipsContent = clipsContent
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
            ZStack {
                content
                    .scaleEffect(displayed.scale)
                    .offset(displayed.offset)
            }
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
            .onChange(of: proxy.size) { _, newSize in
                transform = transform.panned(by: .zero, viewport: newSize)
            }
        }
    }

    /// `transform` (the last *committed* gesture) with any gesture still in flight applied on top,
    /// in the same order a commit would fold it in — see the type's gesture-state doc comment.
    private func displayedTransform(in viewport: CGSize) -> ZoomTransform {
        var result = transform
        if let magnifyPhase {
            result = result.magnified(by: magnifyPhase.magnification, anchor: magnifyPhase.anchor, viewport: viewport)
        }
        if let panTranslation {
            result = result.panned(by: panTranslation, viewport: viewport)
        }
        return result
    }

    private func magnify(in viewport: CGSize) -> some Gesture {
        MagnifyGesture()
            .updating($magnifyPhase) { value, phase, _ in
                guard viewport.width > 0, viewport.height > 0 else { return }
                // `MagnifyGesture.Value.startAnchor` reports `.center` in practice, which
                // pins every pinch to the middle of the viewport. Derive the anchor from the
                // pinch-midpoint location instead — same approach the double-tap uses.
                phase = MagnifyPhase(
                    magnification: value.magnification,
                    anchor: UnitPoint(x: value.startLocation.x / viewport.width, y: value.startLocation.y / viewport.height)
                )
            }
            .onEnded { value in
                guard viewport.width > 0, viewport.height > 0 else { return }
                let anchor = UnitPoint(
                    x: value.startLocation.x / viewport.width,
                    y: value.startLocation.y / viewport.height
                )
                transform = transform.magnified(by: value.magnification, anchor: anchor, viewport: viewport)
            }
    }

    private func pan(in viewport: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($panTranslation) { value, translation, _ in
                // At 1x the drag stays inert so it never fights navigation swipe-back.
                guard transform.isZoomed else { return }
                translation = value.translation
            }
            .onEnded { value in
                guard transform.isZoomed else { return }
                transform = transform.panned(by: value.translation, viewport: viewport)
            }
    }

    /// Double-tap toggles zoom at the tap point; a lone single tap forwards to `onSingleTap`.
    /// `exclusively(before:)` gives the double-tap priority, so SwiftUI holds the single tap until
    /// it's sure a second tap isn't coming — the single fires only when the double fails.
    private func taps(in viewport: CGSize) -> some Gesture {
        let doubleTap = SpatialTapGesture(count: 2)
            .onEnded { value in
                guard viewport.width > 0, viewport.height > 0 else { return }
                let anchor = UnitPoint(
                    x: value.location.x / viewport.width,
                    y: value.location.y / viewport.height
                )
                withAnimation(.snappy) {
                    transform = transform.togglingZoom(at: anchor, viewport: viewport)
                }
            }
        let singleTap = SpatialTapGesture(count: 1)
            .onEnded { _ in onSingleTap() }
        return doubleTap.exclusively(before: singleTap)
    }
}
