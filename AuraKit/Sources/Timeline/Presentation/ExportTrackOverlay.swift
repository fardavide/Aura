import Foundation
import SwiftUI

import CommonDesign
import TimelineDomain

/// The clip drawn on the scrub track: the selected region, its two handles, and the gestures that
/// move them. Sits over `RecordingTimelineTrack`, which dims itself around the same selection.
///
/// The handles are deliberately the opposite of the playhead. The playhead keeps the brand
/// gradient, the dot and the glow, and means *what the video is showing*; these are flat
/// `TextPrimary` ink with no gradient, no glow and no tint — chrome you grab rather than state you
/// read. That contrast is the whole reason the two can share a 72 pt track without being confused
/// for one another, so it is not a detail to soften later.
struct ExportTrackOverlay: View {
    let state: ExportEditorState
    let axis: Axis
    let thickness: CGFloat
    let viewport: TimelineViewport
    let isPlayingSelection: Bool
    let onSelectionChange: (ExportSelection) -> Void

    @Environment(\.colorScheme) private var colorScheme
    /// The selection as the gesture began. Anchoring on it — rather than accumulating deltas —
    /// means a slow drag cannot drift, the same reason the scrub track does it.
    @State private var dragAnchor: ExportSelection?
    @State private var lastMoved: ExportHandleSide = .end
    @GestureState private var activeSide: ExportHandleSide?
    @GestureState private var isMovingRegion = false

    private var layout: ExportTrackLayout {
        ExportTrackLayout(axis: axis, viewport: viewport, thickness: thickness, selection: state.selection)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            selectionRegion
            if state.showsHandles {
                regionDragTarget
                handle(.start)
                handle(.end)
            } else {
                coarseMark
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.showsHandles)
    }

    // MARK: Region

    private var selectionRegion: some View {
        let origin = layout.selectionOrigin
        let length = layout.selectionLength
        return ZStack(alignment: axis == .horizontal ? .bottom : .trailing) {
            Rectangle().fill(.auroraTextPrimary.opacity(colorScheme == .dark ? 0.06 : 0.05))
            rim
            if layout.showsGrabBar {
                Capsule()
                    .fill(isMovingRegion ? AnyShapeStyle(Color.auroraTextPrimary) : AnyShapeStyle(Color.auroraGrabber))
                    .frame(
                        width: axis == .horizontal ? ExportTrackLayout.grabBarSize.width : grabBarThickness,
                        height: axis == .horizontal ? grabBarThickness : ExportTrackLayout.grabBarSize.width
                    )
                    .padding(axis == .horizontal ? .bottom : .trailing, ExportTrackLayout.grabBarInset)
            }
        }
        .frame(
            width: axis == .horizontal ? length : thickness,
            height: axis == .horizontal ? thickness : length
        )
        .offset(
            x: axis == .horizontal ? origin : 0,
            y: axis == .horizontal ? 0 : origin
        )
        .allowsHitTesting(false)
    }

    /// A transparent strip carrying the whole-range drag, inset so each bar keeps the 22 pt either
    /// side of it. Separate from the visual because the region is drawn full-width but must not be
    /// grabbable right where a handle is. `nil` at the one-second minimum, where nothing is left —
    /// and then no gesture exists at all rather than one that fights the handles for the same
    /// pixels.
    @ViewBuilder private var regionDragTarget: some View {
        if state.handlesAreInteractive, let range = layout.regionDragRange {
            let length = range.upperBound - range.lowerBound
            Color.clear
                .frame(
                    width: axis == .horizontal ? length : thickness,
                    height: axis == .horizontal ? thickness : length
                )
                .offset(
                    x: axis == .horizontal ? range.lowerBound : 0,
                    y: axis == .horizontal ? 0 : range.lowerBound
                )
                .contentShape(Rectangle())
                .gesture(regionDrag)
        }
    }

    private var grabBarThickness: CGFloat {
        isMovingRegion ? 4 : ExportTrackLayout.grabBarSize.height
    }

    /// Only the two cross-edges — the edges along the time axis are the handle bars themselves,
    /// and drawing a rim there too would double them.
    @ViewBuilder private var rim: some View {
        let style: AnyShapeStyle = isPlayingSelection
            ? AnyShapeStyle(AuroraGradient.diagonal)
            : AnyShapeStyle(Color.auroraTextPrimary.opacity(0.45))
        ZStack(alignment: axis == .horizontal ? .top : .leading) {
            Rectangle().fill(style)
                .frame(width: axis == .horizontal ? nil : 1.5, height: axis == .horizontal ? 1.5 : nil)
            Rectangle().fill(style)
                .frame(width: axis == .horizontal ? nil : 1.5, height: axis == .horizontal ? 1.5 : nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: axis == .horizontal ? .bottom : .trailing)
        }
    }

    private var regionDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($isMovingRegion) { _, moving, _ in moving = true }
            .onChanged { value in
                let anchor = beganDrag()
                let target = anchor.start.addingTimeInterval(seconds(from: value.translation))
                onSelectionChange(anchor.movingWholeRange(toStart: target, within: state.span))
            }
            .onEnded { _ in dragAnchor = nil }
    }

    // MARK: Handles

    private func handle(_ side: ExportHandleSide) -> some View {
        let bar = layout.position(of: side == .start ? state.selection.start : state.selection.end)
        let isActive = activeSide == side
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.auroraTextPrimary)
                .frame(
                    width: axis == .horizontal ? ExportTrackLayout.barWidth : thickness,
                    height: axis == .horizontal ? thickness : ExportTrackLayout.barWidth
                )
                .offset(
                    x: axis == .horizontal ? bar - ExportTrackLayout.barWidth / 2 : 0,
                    y: axis == .horizontal ? 0 : bar - ExportTrackLayout.barWidth / 2
                )
            knob(side, isActive: isActive)
        }
        .contentShape(Rectangle().path(in: layout.targetRect(side)))
        .gesture(handleDrag(side))
        .allowsHitTesting(state.handlesAreInteractive)
        .accessibilityElement()
        .accessibilityLabel(side == .start ? "Clip start" : "Clip end")
        .accessibilityValue(Text(side == .start ? state.selection.start : state.selection.end, format: .dateTime.hour().minute().second()))
        .accessibilityHint("Swipe up or down to adjust by one second.")
        .accessibilityAdjustableAction { direction in
            let step: TimeInterval = direction == .increment ? 1 : -1
            let moved = side == .start
                ? state.selection.movingStart(to: state.selection.start.addingTimeInterval(step), within: state.span)
                : state.selection.movingEnd(to: state.selection.end.addingTimeInterval(step), within: state.span)
            onSelectionChange(moved)
        }
    }

    private func knob(_ side: ExportHandleSide, isActive: Bool) -> some View {
        let rect = layout.knobRect(side)
        let grown: CGFloat = isActive ? 4 : 0
        return RoundedRectangle(cornerRadius: isActive ? 9 : ExportTrackLayout.knobRadius, style: .continuous)
            .fill(.auroraTextPrimary)
            .overlay { grip }
            .frame(width: rect.width + grown, height: rect.height + grown)
            .position(x: rect.midX, y: rect.midY)
            .animation(.spring(response: 0.18, dampingFraction: 0.85), value: isActive)
    }

    /// Two short bars in the panel's own fill colour — the only mark on the knob, because anything
    /// more at 14 pt wide is noise.
    private var grip: some View {
        let ink = Color.auroraBase.opacity(colorScheme == .dark ? 0.45 : 0.78)
        return HStack(spacing: 2) {
            Capsule().fill(ink).frame(width: 1.5, height: 11)
            Capsule().fill(ink).frame(width: 1.5, height: 11)
        }
        .rotationEffect(.degrees(axis == .horizontal ? 0 : 90))
    }

    private func handleDrag(_ side: ExportHandleSide) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($activeSide) { _, active, _ in active = side }
            .onChanged { value in
                let anchor = beganDrag()
                let shift = seconds(from: value.translation)
                switch side {
                case .start:
                    onSelectionChange(anchor.movingStart(to: anchor.start.addingTimeInterval(shift), within: state.span))
                case .end:
                    onSelectionChange(anchor.movingEnd(to: anchor.end.addingTimeInterval(shift), within: state.span))
                }
            }
            .onEnded { _ in
                dragAnchor = nil
                lastMoved = side
            }
    }

    // MARK: Below Hour

    /// Too narrow for a knob anyone could hit, so the clip becomes a mark with brackets and the
    /// handles are absent rather than drawn and inert.
    private var coarseMark: some View {
        let origin = layout.selectionOrigin
        return ZStack(alignment: axis == .horizontal ? .top : .leading) {
            Rectangle().fill(AuroraGradient.diagonal)
            bracket
            bracket.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: axis == .horizontal ? .bottom : .trailing)
        }
        .frame(
            width: axis == .horizontal ? max(4, layout.selectionLength) : thickness,
            height: axis == .horizontal ? thickness : max(4, layout.selectionLength)
        )
        .offset(
            x: axis == .horizontal ? origin : 0,
            y: axis == .horizontal ? 0 : origin
        )
    }

    private var bracket: some View {
        Rectangle()
            .fill(.auroraTextPrimary)
            .frame(
                width: axis == .horizontal ? 16 : 3,
                height: axis == .horizontal ? 3 : 16
            )
    }

    // MARK: -

    /// A drag's translation in seconds of footage. Vertical runs newest-at-top, so dragging down
    /// runs backwards in time.
    private func seconds(from translation: CGSize) -> TimeInterval {
        let points = axis == .horizontal ? translation.width : -translation.height
        guard viewport.pointsPerHour > 0 else { return 0 }
        return TimeInterval(points / viewport.pointsPerHour) * 3_600
    }

    private func beganDrag() -> ExportSelection {
        if let dragAnchor { return dragAnchor }
        let anchor = state.selection
        dragAnchor = anchor
        return anchor
    }
}
