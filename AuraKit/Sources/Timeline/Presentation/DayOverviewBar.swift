import Foundation
import SwiftUI

import TimelineDomain

/// The whole day at a glance, under the clock: an hourly motion rollup, a severity-colored tick
/// per review marker, hatched stretches with no footage, and — outlined in the accent — the slice
/// of it the scrub track is currently showing. Dragging anywhere on it puts the playhead at that
/// time of day, so a jump from breakfast to midnight is one gesture instead of a long scroll.
struct DayOverviewBar: View {
    let overview: DayOverview
    let instant: Date
    /// The density the scrub track is drawn at. The bar sits directly above that track and is
    /// exactly as wide, so it derives the outlined slice from its own measured width rather than
    /// having the track's length threaded down to it.
    let zoom: TimelineZoom
    let liveEdge: Date
    let onScrubBegin: () -> Void
    let onScrub: (Date) -> Void
    let onScrubEnd: () -> Void

    @State private var isDragging = false

    private static let markerTickThickness: CGFloat = 2
    private static let markerTickLength: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                draw(in: context, size: size, visible: visible(forWidth: size.width))
            }
            .contentShape(Rectangle())
            // A scrub, not a per-frame seek: the drag follows with cheap tolerant seeks and the
            // release settles exactly — and playback the user was watching resumes afterwards.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            onScrubBegin()
                        }
                        onScrub(instant(atX: value.location.x, width: geometry.size.width))
                    }
                    .onEnded { _ in
                        isDragging = false
                        onScrubEnd()
                    }
            )
        }
        .frame(height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityLabel("Day overview")
    }

    private func draw(in context: GraphicsContext, size: CGSize, visible: TimeRange) {
        let day = overview.day
        let length = day.end.timeIntervalSince(day.start)
        guard length > 0, size.width > 0 else { return }
        func x(_ instant: Date) -> CGFloat {
            CGFloat(instant.timeIntervalSince(day.start) / length) * size.width
        }

        if liveEdge < day.end {
            TimelineHatch.fill(
                CGRect(x: max(0, x(liveEdge)), y: 0, width: size.width, height: size.height),
                in: context
            )
        }
        for gap in overview.gaps {
            TimelineHatch.fill(
                CGRect(x: x(gap.start), y: 0, width: max(1, x(gap.end) - x(gap.start)), height: size.height),
                in: context
            )
        }

        let hourWidth = size.width / CGFloat(DayOverview.hoursInDay)
        let maxBarHeight = size.height - Self.markerTickLength
        for (hour, intensity) in overview.hourlyMotion.enumerated() where intensity > 0 {
            let height = max(1.5, maxBarHeight * CGFloat(intensity) / 100)
            context.fill(
                Path(
                    CGRect(
                        x: CGFloat(hour) * hourWidth + 0.6,
                        y: size.height - height,
                        width: hourWidth - 1.2,
                        height: height
                    )
                ),
                with: .color(TimelineTrackStyle.motionColor)
            )
        }

        for marker in overview.markers {
            context.fill(
                Path(
                    CGRect(
                        x: x(marker.start) - Self.markerTickThickness / 2,
                        y: 0,
                        width: Self.markerTickThickness,
                        height: Self.markerTickLength
                    )
                ),
                with: .color(TimelineTrackStyle.markerColor(for: marker.severity))
            )
        }

        let window = CGRect(
            x: max(0, x(visible.start)),
            y: 0.6,
            width: max(5, min(size.width, x(visible.end)) - max(0, x(visible.start))),
            height: size.height - 1.2
        )
        let windowShape = Path(roundedRect: window, cornerRadius: 4)
        context.fill(windowShape, with: .style(.tint.opacity(0.16)))
        context.stroke(windowShape, with: .style(.tint), lineWidth: 1.3)

        var playhead = Path()
        playhead.move(to: CGPoint(x: x(instant), y: 0))
        playhead.addLine(to: CGPoint(x: x(instant), y: size.height))
        context.stroke(playhead, with: .style(.tint), lineWidth: 1.6)
    }

    private func visible(forWidth width: CGFloat) -> TimeRange {
        TimelineViewport(center: instant, pointsPerHour: zoom.pointsPerHour, length: width).visible
    }

    private func instant(atX x: CGFloat, width: CGFloat) -> Date {
        guard width > 0 else { return overview.day.start }
        let fraction = min(1, max(0, x / width))
        let length = overview.day.end.timeIntervalSince(overview.day.start)
        return overview.day.start.addingTimeInterval(length * Double(fraction))
    }
}

/// The `00 04 08 … 24` scale printed under the day bar.
struct DayOverviewScale: View {
    var body: some View {
        HStack {
            ForEach(Array(stride(from: 0, through: 24, by: 4)), id: \.self) { hour in
                Text(hour < 10 ? "0\(hour)" : "\(hour)")
                if hour != 24 { Spacer(minLength: 0) }
            }
        }
        .font(.system(size: 9.5, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }
}
