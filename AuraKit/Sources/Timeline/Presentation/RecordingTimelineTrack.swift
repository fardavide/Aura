import Foundation
import SwiftUI

import TimelineDomain

/// The scrub track for one camera: motion rising from the baseline, a lane of review markers above
/// it, hatched stretches with no footage, a divider at each midnight, and a dashed line at the live
/// edge. Centre-anchored — the playhead is fixed at the middle, drawn by the enclosing view, and
/// this is the footage sliding under it.
///
/// Laid out along `axis`. Horizontal runs past→future left→right with the lane on top and the
/// motion rising from the bottom; vertical mirrors it — newest at the top, lane on the left, motion
/// growing leftward from the right edge — so the cross-axis measurements are the same numbers in
/// both.
struct RecordingTimelineTrack: View {
    let axis: Axis
    let viewport: TimelineViewport
    let timeline: DayTimeline
    let span: TimeRange

    @Environment(\.calendar) private var calendar

    /// Cross-axis room reserved for the marker lane, above/left of the motion.
    private static let laneInset: CGFloat = 3
    private static let laneThickness: CGFloat = 8
    /// Clear space between the lane and the tallest a motion bar may grow.
    private static let laneClearance: CGFloat = 6

    var body: some View {
        // Captured here: the draw closure runs after `body` returns.
        let calendar = calendar
        return Canvas { context, size in
            let geometry = TrackGeometry(axis: axis, viewport: viewport, size: size)
            let visible = viewport.visible

            if span.start > visible.start {
                context.fill(
                    Path(geometry.rect(from: visible.start, to: span.start, crossFrom: 0, crossTo: geometry.crossExtent)),
                    with: .color(.gray.opacity(0.05))
                )
            }
            if span.end < visible.end {
                TimelineHatch.fill(
                    geometry.rect(from: span.end, to: visible.end, crossFrom: 0, crossTo: geometry.crossExtent),
                    in: context
                )
            }
            for gap in timeline.gaps where gap.range.end > visible.start && gap.range.start < visible.end {
                TimelineHatch.fill(
                    geometry.rect(from: gap.range.start, to: gap.range.end, crossFrom: 0, crossTo: geometry.crossExtent),
                    in: context
                )
            }

            drawDayDividers(in: context, geometry: geometry, calendar: calendar)
            drawMotion(in: context, geometry: geometry)
            drawBaseline(in: context, geometry: geometry)
            drawMarkers(in: context, geometry: geometry)

            if visible.contains(span.end) {
                context.stroke(
                    geometry.line(at: span.end),
                    with: .color(.secondary),
                    style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])
                )
            }
        }
    }

    private func drawDayDividers(in context: GraphicsContext, geometry: TrackGeometry, calendar: Calendar) {
        let visible = viewport.visible
        var midnight = calendar.startOfDay(for: visible.start)
        while midnight < visible.end {
            if midnight > visible.start {
                context.stroke(geometry.line(at: midnight), with: .color(.secondary.opacity(0.35)), lineWidth: 1)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: midnight) else { return }
            midnight = next
        }
    }

    /// Bars sized to the bucket the server actually returned, so the track reads at the resolution
    /// of the data rather than pretending to a finer one.
    private func drawMotion(in context: GraphicsContext, geometry: TrackGeometry) {
        let visible = viewport.visible
        let bucketDuration = timeline.motionBucketDuration
        let maxLength = geometry.crossExtent - Self.laneInset - Self.laneThickness - Self.laneClearance
        guard maxLength > 0 else { return }

        for bucket in timeline.motion where bucket.intensity > 0 {
            let end = bucket.time.addingTimeInterval(bucketDuration)
            guard end > visible.start, bucket.time < visible.end else { continue }
            let length = max(2, maxLength * CGFloat(bucket.intensity) / 100)
            let bar = geometry.rect(
                from: bucket.time,
                to: end,
                crossFrom: geometry.crossExtent - length,
                crossTo: geometry.crossExtent
            )
            // A hairline between neighbours: without it, contiguous buckets weld into one block and
            // the strip stops reading as a series of measurements.
            context.fill(Path(geometry.narrowed(bar, by: 1)), with: .color(.green))
        }
    }

    private func drawBaseline(in context: GraphicsContext, geometry: TrackGeometry) {
        context.stroke(geometry.baseline, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
    }

    private func drawMarkers(in context: GraphicsContext, geometry: TrackGeometry) {
        let visible = viewport.visible
        for marker in timeline.markers {
            // An in-progress marker has no end yet; it runs to the live edge.
            let end = marker.end ?? span.end
            guard end > visible.start, marker.start < visible.end else { continue }
            var pill = geometry.rect(
                from: marker.start,
                to: end,
                crossFrom: Self.laneInset,
                crossTo: Self.laneInset + Self.laneThickness
            )
            // A marker lasting a second or two would otherwise be invisible at week density.
            pill = geometry.lengthened(pill, toAtLeast: Self.laneThickness / 2)
            context.fill(
                Path(roundedRect: pill, cornerRadius: Self.laneThickness / 2),
                with: .color(marker.severity == .alert ? .red : .orange)
            )
        }
    }
}

/// Maps a time range and a cross-axis band onto a rectangle for the chosen axis, so every shape is
/// expressed once in time terms rather than twice in points.
private struct TrackGeometry {
    let axis: Axis
    let viewport: TimelineViewport
    let size: CGSize

    var crossExtent: CGFloat { axis == .horizontal ? size.height : size.width }
    private var timeExtent: CGFloat { axis == .horizontal ? size.width : size.height }

    func rect(from start: Date, to end: Date, crossFrom: CGFloat, crossTo: CGFloat) -> CGRect {
        let low = viewport.position(of: start)
        let high = viewport.position(of: end)
        switch axis {
        case .horizontal:
            return CGRect(x: low, y: crossFrom, width: high - low, height: crossTo - crossFrom)
        case .vertical:
            // Newest at the top, so the axis is flipped against the forward position.
            return CGRect(x: crossFrom, y: timeExtent - high, width: crossTo - crossFrom, height: high - low)
        }
    }

    /// A hairline across the whole cross axis at one instant — a day divider or the live edge.
    func line(at instant: Date) -> Path {
        let rect = rect(from: instant, to: instant, crossFrom: 0, crossTo: crossExtent)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }

    /// The line the motion bars stand on, along the far cross edge.
    var baseline: Path {
        var path = Path()
        switch axis {
        case .horizontal:
            path.move(to: CGPoint(x: 0, y: size.height - 0.5))
            path.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
        case .vertical:
            path.move(to: CGPoint(x: size.width - 0.5, y: 0))
            path.addLine(to: CGPoint(x: size.width - 0.5, y: size.height))
        }
        return path
    }

    /// Trims a rect along the **time** axis, never below a hairline — the separator between
    /// neighbouring bars, which must not consume a bar that is already thin.
    func narrowed(_ rect: CGRect, by points: CGFloat) -> CGRect {
        switch axis {
        case .horizontal:
            let trimmed = max(1, rect.width - points)
            return CGRect(x: rect.minX, y: rect.minY, width: trimmed, height: rect.height)
        case .vertical:
            let trimmed = max(1, rect.height - points)
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: trimmed)
        }
    }

    /// Grows a rect along the **time** axis to a minimum, keeping it centred on what it covers.
    func lengthened(_ rect: CGRect, toAtLeast minimum: CGFloat) -> CGRect {
        switch axis {
        case .horizontal:
            guard rect.width < minimum else { return rect }
            return CGRect(x: rect.midX - minimum / 2, y: rect.minY, width: minimum, height: rect.height)
        case .vertical:
            guard rect.height < minimum else { return rect }
            return CGRect(x: rect.minX, y: rect.midY - minimum / 2, width: rect.width, height: minimum)
        }
    }
}

extension DayTimeline {
    /// How much time one motion bucket covers, read off the buckets themselves — the server picks
    /// the scale from the span, so it isn't a constant the client can assume.
    /// Read off the first two buckets rather than by scanning: the server returns them in
    /// ascending order at a uniform scale, and this is asked for on every redraw.
    var motionBucketDuration: TimeInterval {
        guard motion.count > 1 else { return 60 }
        return max(1, motion[1].time.timeIntervalSince(motion[0].time))
    }
}
