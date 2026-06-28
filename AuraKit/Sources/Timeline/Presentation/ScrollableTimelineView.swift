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
            .overlay(alignment: .center) {
                Capsule()
                    .fill(.primary)
                    .frame(width: 3)
                    .shadow(radius: 1)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 56)
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
            func x(_ time: Date) -> CGFloat {
                CGFloat(time.timeIntervalSince(span.start) / duration) * size.width
            }

            for gap in timeline.gaps {
                let start = x(gap.range.start)
                let end = x(gap.range.end)
                context.fill(
                    Path(CGRect(x: start, y: 0, width: Swift.max(1, end - start), height: size.height)),
                    with: .color(.gray.opacity(0.1))
                )
            }

            let barWidth: CGFloat = 3
            for bucket in timeline.motion where bucket.intensity > 0 {
                let height = Swift.max(barWidth, size.height * CGFloat(bucket.intensity) / 100)
                let rect = CGRect(x: x(bucket.time) - barWidth / 2, y: size.height - height, width: barWidth, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color(at: bucket.time).opacity(0.9)))
            }
        }
        .frame(width: width)
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
