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

    @State private var transform = ZoomTransform.standard()
    /// Committed transform captured when a gesture starts; the gestures' cumulative
    /// values apply to this base so magnify and pan can update concurrently without
    /// drift or un-clamped intermediate states.
    @State private var gestureBase: ZoomTransform?
    @State private var activeMagnification: CGFloat = 1
    @State private var activeAnchor: UnitPoint = .center
    @State private var activeTranslation: CGSize = .zero
    @State private var isMagnifying = false
    @State private var isPanning = false

    public init(onSingleTap: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onSingleTap = onSingleTap
        self.content = content()
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                content
                    .scaleEffect(transform.scale)
                    .offset(transform.offset)
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
        .clipped()
    }

    private func magnify(in viewport: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard viewport.width > 0, viewport.height > 0 else { return }
                isMagnifying = true
                activeMagnification = value.magnification
                // `MagnifyGesture.Value.startAnchor` reports `.center` in practice, which
                // pins every pinch to the middle of the viewport. Derive the anchor from the
                // pinch-midpoint location instead — same approach the double-tap uses.
                activeAnchor = UnitPoint(
                    x: value.startLocation.x / viewport.width,
                    y: value.startLocation.y / viewport.height
                )
                applyActiveGestures(in: viewport)
            }
            .onEnded { _ in
                isMagnifying = false
                commitIfGesturesEnded()
            }
    }

    private func pan(in viewport: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                // At 1x the drag stays inert so it never fights navigation swipe-back.
                guard (gestureBase ?? transform).isZoomed else { return }
                isPanning = true
                activeTranslation = value.translation
                applyActiveGestures(in: viewport)
            }
            .onEnded { _ in
                isPanning = false
                commitIfGesturesEnded()
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

    private func applyActiveGestures(in viewport: CGSize) {
        let base = gestureBase ?? transform
        gestureBase = base
        transform = base
            .magnified(by: activeMagnification, anchor: activeAnchor, viewport: viewport)
            .panned(by: activeTranslation, viewport: viewport)
    }

    private func commitIfGesturesEnded() {
        guard !isMagnifying, !isPanning else { return }
        gestureBase = nil
        activeMagnification = 1
        activeAnchor = .center
        activeTranslation = .zero
    }
}
