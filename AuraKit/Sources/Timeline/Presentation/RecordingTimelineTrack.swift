import Foundation
import SwiftUI

import CommonDesign
import TimelineDomain

/// The scrub track for one camera: motion rising from the dark well floor, a lane of review markers
/// above it, hatched stretches with no footage, a divider at each midnight, and a dashed line at the
/// live edge. Centre-anchored — the playhead is fixed at the middle, drawn by the enclosing view,
/// and this is the footage sliding under it.
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
    /// The export selection to hold at full strength while everything outside it recedes. `nil`
    /// outside export mode — and also whenever dimming would mislead rather than focus: below Hour
    /// density, where the selection is a few points wide, and over a range holding no footage at
    /// all, where there is nothing to emphasise.
    var emphasis: TimeRange?

    @Environment(\.calendar) private var calendar

    var body: some View {
        // Captured here: the draw closure runs after `body` returns.
        let calendar = calendar
        return Canvas { context, size in
            let geometry = TrackGeometry(axis: axis, viewport: viewport, size: size)
            guard let emphasis else {
                drawFootage(in: context, geometry: geometry, calendar: calendar)
                drawMarkers(in: context, geometry: geometry)
                return
            }
            let inside = Path(
                geometry.rect(from: emphasis.start, to: emphasis.end, crossFrom: 0, crossTo: geometry.crossExtent)
            )
            // Outside the clip: hue removed and well down, so the selection is the only thing the
            // eye lands on. Deliberately below the contrast floor — nothing load-bearing is carried
            // by it, because the boundary itself is the handles and the ruler.
            context.drawLayer { layer in
                layer.clip(to: inside, options: .inverse)
                layer.addFilter(.grayscale(1))
                layer.opacity = Self.outsideOpacity
                drawFootage(in: layer, geometry: geometry, calendar: calendar)
            }
            // Markers are exempt, and sit higher than the rest of the dimmed content with their hue
            // intact: finding the event you want to clip is the whole task.
            context.drawLayer { layer in
                layer.clip(to: inside, options: .inverse)
                layer.opacity = Self.outsideMarkerOpacity
                drawMarkers(in: layer, geometry: geometry)
            }
            context.drawLayer { layer in
                layer.clip(to: inside)
                drawFootage(in: layer, geometry: geometry, calendar: calendar)
                drawMarkers(in: layer, geometry: geometry)
            }
        }
    }

    private static let outsideOpacity: Double = 0.32
    private static let outsideMarkerOpacity: Double = 0.55

    /// Everything but the markers: the hatching, the day dividers, the motion and the live edge.
    private func drawFootage(in context: GraphicsContext, geometry: TrackGeometry, calendar: Calendar) {
        let visible = viewport.visible
        if span.start > visible.start {
            TimelineHatch.fill(
                geometry.rect(from: visible.start, to: span.start, crossFrom: 0, crossTo: geometry.crossExtent),
                in: context
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

        if visible.contains(span.end) {
            context.stroke(geometry.line(at: span.end), with: AuroraTrack.nowLine, style: AuroraTrack.nowLineStyle)
        }
    }

    private func drawDayDividers(in context: GraphicsContext, geometry: TrackGeometry, calendar: Calendar) {
        let visible = viewport.visible
        var midnight = calendar.startOfDay(for: visible.start)
        while midnight < visible.end {
            if midnight > visible.start {
                context.stroke(geometry.line(at: midnight), with: AuroraTrack.midnight, lineWidth: AuroraTrack.midnightLineWidth)
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
        let maxLength = geometry.crossExtent
            - TimelineTrackStyle.laneInset - TimelineTrackStyle.laneThickness - TimelineTrackStyle.laneClearance
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
            context.fill(
                Path(geometry.narrowed(bar, by: TimelineTrackStyle.motionBarSeparator)),
                with: .color(TimelineTrackStyle.motionColor(intensity: bucket.intensity))
            )
        }
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
                crossFrom: TimelineTrackStyle.laneInset,
                crossTo: TimelineTrackStyle.laneInset + TimelineTrackStyle.laneThickness
            )
            pill = geometry.lengthened(pill, toAtLeast: TimelineTrackStyle.minimumMarkerLength)
            TimelineTrackStyle.fillMarkerPill(pill, severity: marker.severity, in: context)
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
