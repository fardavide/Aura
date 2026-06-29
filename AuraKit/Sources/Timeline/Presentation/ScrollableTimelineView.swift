import Foundation
import SwiftUI

import TimelineDomain

/// The Liquid-Glass scrubber: a date/time header, a scrollable activity **histogram** (motion
/// height, colored by review severity, gaps dimmed) with a fixed center playhead, and a legend.
/// Scrolling/panning the histogram sets the scrub time.
struct ScrollableTimelineView: View {
    let span: TimeRange
    let timeline: DayTimeline
    let clock: ScrubClock
    let onScrub: (Date) -> Void

    @State private var zoom: TimelineZoom = .day

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            histogram
            legend
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            TimelineClockLabel(clock: clock)
            Spacer()
            Button(zoom.title) { zoom = zoom.next }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.glass)
        }
    }

    private var histogram: some View {
        GeometryReader { geo in
            let viewportWidth = geo.size.width
            let hours = span.end.timeIntervalSince(span.start) / 3600
            let contentWidth = Swift.max(viewportWidth, CGFloat(hours) * zoom.pointsPerHour)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: viewportWidth / 2)
                    HistogramTrack(span: span, timeline: timeline, width: contentWidth)
                    Color.clear.frame(width: viewportWidth / 2)
                }
            }
            .defaultScrollAnchor(.trailing)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.x
            } action: { _, offsetX in
                guard contentWidth > 0 else { return }
                let fraction = min(1, Swift.max(0, offsetX / contentWidth))
                onScrub(span.start.addingTimeInterval(span.end.timeIntervalSince(span.start) * Double(fraction)))
            }
            .background(.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
            }
            .overlay(alignment: .center) { playhead }
        }
        .frame(height: 68)
    }

    /// The fixed center playhead: a blue line.
    private var playhead: some View {
        GeometryReader { geo in
            let midX = geo.size.width / 2
            Path { path in
                path.move(to: CGPoint(x: midX, y: 0))
                path.addLine(to: CGPoint(x: midX, y: geo.size.height))
            }
            .stroke(.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .allowsHitTesting(false)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(.green, "Motion")
            legendItem(.red, "Alert")
            legendItem(.orange, "Detection")
            legendItem(.gray.opacity(0.4), "No footage")
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}

/// Date + large time readout; isolated so only it re-renders as the clock moves while scrubbing.
private struct TimelineClockLabel: View {
    let clock: ScrubClock

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(clock.instant, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(clock.instant, format: .dateTime.hour().minute())
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
    }
}

private struct HistogramTrack: View {
    let span: TimeRange
    let timeline: DayTimeline
    let width: CGFloat

    var body: some View {
        Canvas { context, size in
            let duration = span.end.timeIntervalSince(span.start)
            guard duration > 0 else { return }
            let topLabelArea: CGFloat = 13
            func x(_ time: Date) -> CGFloat {
                CGFloat(time.timeIntervalSince(span.start) / duration) * size.width
            }

            drawGaps(in: context, size: size, x: x)
            drawHourLabels(in: context, size: size, x: x)

            let barWidth: CGFloat = 3
            let maxBarHeight = size.height - topLabelArea
            for bucket in timeline.motion where bucket.intensity > 0 {
                let height = Swift.max(barWidth, maxBarHeight * CGFloat(bucket.intensity) / 100)
                // Anchor bars to the bottom of the track.
                let rect = CGRect(x: x(bucket.time) - barWidth / 2, y: size.height - height, width: barWidth, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color(at: bucket.time).opacity(0.9)))
            }
        }
        .frame(width: width)
    }

    /// No-footage ranges drawn as a diagonal hatch — distinct from "recorded but no motion".
    private func drawGaps(in context: GraphicsContext, size: CGSize, x: (Date) -> CGFloat) {
        for gap in timeline.gaps {
            let start = x(gap.range.start)
            let end = Swift.max(start + 1, x(gap.range.end))
            let rect = CGRect(x: start, y: 0, width: end - start, height: size.height)
            context.fill(Path(rect), with: .color(.gray.opacity(0.08)))
            context.drawLayer { layer in
                layer.clip(to: Path(rect))
                var hatch = Path()
                var hatchX = rect.minX - size.height
                while hatchX < rect.maxX {
                    hatch.move(to: CGPoint(x: hatchX, y: rect.maxY))
                    hatch.addLine(to: CGPoint(x: hatchX + size.height, y: rect.minY))
                    hatchX += 7
                }
                layer.stroke(hatch, with: .color(.gray.opacity(0.3)), lineWidth: 1)
            }
        }
    }

    /// Faint time labels every 6h at the top, leaving the bars flush to the bottom.
    private func drawHourLabels(in context: GraphicsContext, size: CGSize, x: (Date) -> CGFloat) {
        let calendar = Calendar.current
        guard var tick = calendar.nextDate(
            after: span.start, matching: DateComponents(minute: 0), matchingPolicy: .nextTime
        ) else { return }
        while tick < span.end {
            if calendar.component(.hour, from: tick).isMultiple(of: 6) {
                context.draw(
                    Text(tick, format: .dateTime.hour().minute()).font(.system(size: 9)).foregroundStyle(.tertiary),
                    at: CGPoint(x: x(tick), y: 7),
                    anchor: .center
                )
            }
            guard let next = calendar.date(byAdding: .hour, value: 1, to: tick) else { return }
            tick = next
        }
    }

    /// Bar color: red over an alert, orange over a detection, else green (motion).
    private func color(at time: Date) -> Color {
        for marker in timeline.markers {
            let end = marker.end ?? span.end
            if time >= marker.start, time < end {
                return marker.severity == .alert ? .red : .orange
            }
        }
        return .green
    }
}

/// How densely the timeline is drawn — the "Day" pill cycles through these.
private enum TimelineZoom: CaseIterable {
    case hour, day, week

    var pointsPerHour: CGFloat {
        switch self {
        case .hour: 480
        case .day: 120
        case .week: 36
        }
    }

    var title: String {
        switch self {
        case .hour: "Hour"
        case .day: "Day"
        case .week: "Week"
        }
    }

    var next: TimelineZoom {
        let all = Self.allCases
        return all[(all.firstIndex(of: self).map { $0 + 1 } ?? 0) % all.count]
    }
}
