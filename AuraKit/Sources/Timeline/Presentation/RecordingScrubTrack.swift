import Foundation
import SwiftUI

/// The draggable scrub track with its ruler and the fixed centre playhead.
///
/// The length it draws against is read inside a `GeometryReader`, not stored — a measurement routed
/// through `@State` settles a pass later, which leaves the track drawn against a stale window for
/// one frame (and makes a screenshot of it depend on which pass was captured). The cross-axis size
/// is a sum of constants, so the reader has the definite frame it needs.
///
/// The drag is anchored: the instant the gesture started plus the gesture's **total** translation,
/// rather than a running sum of deltas — so a slow drag can't accumulate rounding, and letting go
/// and grabbing again always resumes from where the playhead actually is.
struct RecordingScrubTrack: View {
    let axis: Axis
    let state: RecordingDetailState
    let actions: RecordingDetailActions
    let filmstrip: RecordingFilmstripStore
    /// The track's cross-axis size — how tall (horizontal) or wide (vertical) the footage band is.
    let thickness: CGFloat
    /// The glide running after a thrown release. Owned by the panel, which cancels it whenever
    /// another control takes the playhead.
    @Binding var flingTask: Task<Void, Never>?

    @Environment(\.calendar) private var calendar
    @State private var dragAnchor: Date?
    /// Live while the system considers the drag active. SwiftUI resets it when a gesture is
    /// *cancelled* (an incoming call, a rotation) without calling `onEnded` — the reset is how
    /// the scrub still gets settled instead of stranding playback paused.
    @GestureState private var dragActive = false

    /// Keeps a label from being half-cut at either end of the ruler.
    private static let rulerEdgeInset: CGFloat = 18
    private static let rulerThickness: CGFloat = 15
    private static let rulerWidth: CGFloat = 42
    private static let spacing: CGFloat = 5
    private static let cornerRadius: CGFloat = 12

    @ViewBuilder var body: some View {
        switch axis {
        case .horizontal:
            GeometryReader { proxy in
                VStack(spacing: Self.spacing) {
                    trackBox(length: proxy.size.width).frame(height: thickness)
                    ruler(length: proxy.size.width).frame(height: Self.rulerThickness)
                }
            }
            .frame(height: thickness + Self.spacing + Self.rulerThickness)
        case .vertical:
            GeometryReader { proxy in
                HStack(spacing: 4) {
                    ruler(length: proxy.size.height).frame(width: Self.rulerWidth)
                    trackBox(length: proxy.size.height).frame(width: thickness)
                }
            }
            .frame(width: Self.rulerWidth + 4 + thickness)
        }
    }

    private func viewport(length: CGFloat) -> TimelineViewport {
        TimelineViewport(center: state.instant, pointsPerHour: state.zoom.pointsPerHour, length: length)
    }

    private func trackBox(length: CGFloat) -> some View {
        RecordingTimelineTrack(
            axis: axis,
            viewport: viewport(length: length),
            timeline: state.dayTimeline,
            span: state.span
        )
        // Behind the canvas, so the motion, markers and hatching stay legible over the stills.
        .background { filmstripBackground(length: length) }
        .background(.fill.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay { playhead }
        .contentShape(Rectangle())
        .gesture(drag(length: length))
        .onChange(of: dragActive) { _, active in
            // A cancelled drag never reaches `onEnded` — settle the scrub it left open.
            guard !active, dragAnchor != nil else { return }
            dragAnchor = nil
            actions.endScrub()
        }
        .accessibilityLabel("Timeline")
        .accessibilityValue(Text(state.instant, format: .dateTime.hour().minute().second()))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: actions.skip(60)
            case .decrement: actions.skip(-60)
            @unknown default: break
            }
        }
    }

    /// The design's Hour-zoom filmstrip. Only at that density: a day or week of ten-minute stills
    /// would be sub-cell-width noise, and coarser grids would re-render every cell on each zoom.
    @ViewBuilder private func filmstripBackground(length: CGFloat) -> some View {
        switch state.zoom {
        case .hour:
            RecordingFilmstrip(
                axis: axis,
                viewport: viewport(length: length),
                span: state.span,
                store: filmstrip
            )
        case .day, .week:
            EmptyView()
        }
    }

    /// A line across the track at the centre with a small knob at its head — the one thing on the
    /// panel that never moves, because everything else is measured against it.
    private var playhead: some View {
        ZStack(alignment: axis == .horizontal ? .top : .leading) {
            Rectangle()
                .fill(.tint)
                .frame(width: axis == .horizontal ? 2 : nil, height: axis == .vertical ? 2 : nil)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.tint)
                .frame(width: 12, height: 12)
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(.background, lineWidth: 2)
                }
                .offset(
                    x: axis == .horizontal ? 0 : -3,
                    y: axis == .horizontal ? -3 : 0
                )
        }
        .allowsHitTesting(false)
    }

    private func drag(length: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragActive) { _, active, _ in active = true }
            .onChanged { value in
                let anchor = dragAnchor ?? {
                    // The panel's coordinated `beginScrub` catches any glide still running; the
                    // scrub the glide began stays open, so the resume intent survives the grab.
                    actions.beginScrub()
                    dragAnchor = state.instant
                    return state.instant
                }()
                // Horizontal: dragging right pulls the past under the playhead, so the shift is
                // negated. Vertical runs newest-at-top, so dragging down runs forward.
                let shift = axis == .horizontal ? -value.translation.width : value.translation.height
                let anchored = TimelineViewport(
                    center: anchor,
                    pointsPerHour: state.zoom.pointsPerHour,
                    length: length
                )
                actions.scrub(anchored.center(shiftedByPoints: shift))
            }
            .onEnded { value in
                dragAnchor = nil
                let axisVelocity = axis == .horizontal ? -value.velocity.width : value.velocity.height
                guard let fling = ScrubFling(velocity: axisVelocity) else {
                    actions.endScrub()
                    return
                }
                glide(fling, length: length)
            }
    }

    /// Runs a released throw to its natural stop: the track keeps sliding along the deceleration
    /// curve, then the scrub settles exactly where the glide ended. The span's edges stop a glide
    /// dead — there is nothing past them to slide onto.
    private func glide(_ fling: ScrubFling, length: CGFloat) {
        let viewport = TimelineViewport(
            center: state.instant,
            pointsPerHour: state.zoom.pointsPerHour,
            length: length
        )
        flingTask = Task { @MainActor in
            var elapsed: TimeInterval = 0
            while !Task.isCancelled, elapsed < fling.duration {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
                elapsed += 0.016
                let target = viewport.center(shiftedByPoints: fling.offset(at: min(elapsed, fling.duration)))
                actions.scrub(target)
                if target <= state.span.start || target >= state.span.end { break }
            }
            guard !Task.isCancelled else { return }
            flingTask = nil
            actions.endScrub()
        }
    }

    private func ruler(length: CGFloat) -> some View {
        let ticks = TimelineRulerTicks.ticks(
            in: viewport(length: length),
            zoom: state.zoom,
            calendar: calendar,
            edgeInset: Self.rulerEdgeInset
        )
        return ZStack(alignment: .topLeading) {
            // Claims the full cross-axis size so `.position` has a box to place labels in.
            Color.clear
            ForEach(ticks) { tick in
                label(for: tick)
                    .fixedSize()
                    .position(
                        x: axis == .horizontal ? tick.position : Self.rulerWidth / 2,
                        y: axis == .horizontal ? Self.rulerThickness / 2 : length - tick.position
                    )
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .monospacedDigit()
        .accessibilityHidden(true)
    }

    @ViewBuilder private func label(for tick: TimelineRulerTick) -> some View {
        if tick.isDayBoundary {
            Text(tick.instant, format: .dateTime.weekday(.abbreviated))
                .foregroundStyle(.secondary)
        } else {
            Text(tick.instant, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                .foregroundStyle(.tertiary)
        }
    }
}
