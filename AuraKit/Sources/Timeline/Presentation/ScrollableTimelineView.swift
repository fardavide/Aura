import Foundation
import SwiftUI

import TimelineDomain

/// The Liquid-Glass scrubber: a time header, a scrollable activity **histogram** (motion length,
/// colored by review severity, gaps dimmed) with a fixed center playhead, and — horizontal only —
/// a legend. Scrolling/panning the histogram sets the scrub time.
///
/// Laid out along `axis`: horizontal (a wide card floated at the bottom) or vertical (a tall card
/// on the right, for iPhone landscape). Time always reads start→end along the scroll axis — left→
/// right when horizontal, top→bottom when vertical — with the newest end anchored under the playhead.
struct ScrollableTimelineView: View {
    let axis: Axis
    let span: TimeRange
    let timeline: DayTimeline
    let clock: ScrubClock
    let onScrub: (Date) -> Void

    @State private var zoom: TimelineZoom = .day

    var body: some View {
        glassCard
            .padding(axis == .vertical ? .vertical : .horizontal)
            .padding(axis == .vertical ? .trailing : .bottom, 8)
    }

    @ViewBuilder private var glassCard: some View {
        if axis == .vertical {
            // Measure the available space and size the content to it explicitly: `maxHeight: .infinity`
            // does not survive `glassEffect` on-device (the glass hugs the header), so the histogram
            // would collapse. A definite frame from a GeometryReader makes the card span the full height.
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 12) {
                    header
                    histogram
                }
                .padding(16)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                header
                histogram
                legend
            }
            .padding(16)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }

    @ViewBuilder private var header: some View {
        if axis == .vertical {
            // The slim card stacks the readout over the zoom pill (no room for them side by side).
            VStack(alignment: .leading, spacing: 10) {
                TimelineClockLabel(clock: clock, axis: .vertical)
                Button { zoom = zoom.next } label: {
                    Label(zoom.title, systemImage: zoom.icon)
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.glass)
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                TimelineClockLabel(clock: clock, axis: .horizontal)
                Spacer()
                Button(zoom.title) { zoom = zoom.next }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.glass)
            }
        }
    }

    private var histogram: some View {
        GeometryReader { geo in
            let isVertical = axis == .vertical
            let viewport = isVertical ? geo.size.height : geo.size.width
            let hours = span.end.timeIntervalSince(span.start) / 3600
            let contentLength = Swift.max(viewport, CGFloat(hours) * zoom.pointsPerHour)
            ScrollView(isVertical ? .vertical : .horizontal, showsIndicators: false) {
                scrollStack {
                    endSpacer(viewport / 2)
                    HistogramTrack(axis: axis, span: span, timeline: timeline, length: contentLength)
                    endSpacer(viewport / 2)
                }
            }
            // Vertical anchors the live edge at the top and runs into the past downward, so scrolling
            // *up* reveals older footage. Horizontal anchors the live edge at the trailing edge.
            .defaultScrollAnchor(isVertical ? .top : .trailing)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                isVertical ? geometry.contentOffset.y : geometry.contentOffset.x
            } action: { _, offset in
                guard contentLength > 0 else { return }
                let fraction = min(1, Swift.max(0, offset / contentLength))
                let range = span.end.timeIntervalSince(span.start)
                let time = isVertical
                    ? span.end.addingTimeInterval(-range * Double(fraction))
                    : span.start.addingTimeInterval(range * Double(fraction))
                onScrub(time)
            }
            // Pause auto-refresh while the user is panning so a tick can't yank the histogram.
            .onScrollPhaseChange { _, phase in
                if phase == .idle { clock.endScrub() } else { clock.beginScrub() }
            }
            // Guard against isScrubbing getting stuck if the view disappears mid-deceleration.
            .onDisappear { clock.endScrub() }
            .background(.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
            }
            .overlay(alignment: .center) { playhead }
        }
        // Horizontal: a fixed 68pt strip (as the bottom card). Vertical: claim all the height the
        // full-height card leaves below the header, so the histogram (and the glass) fill it.
        .frame(height: axis == .horizontal ? 68 : nil)
        .frame(maxHeight: axis == .vertical ? .infinity : nil)
    }

    /// Lays the two padding spacers and the track along the scroll axis.
    @ViewBuilder
    private func scrollStack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if axis == .vertical {
            VStack(spacing: 0, content: content)
        } else {
            HStack(spacing: 0, content: content)
        }
    }

    /// A half-viewport spacer so the track's start/end can reach the centered playhead.
    private func endSpacer(_ half: CGFloat) -> some View {
        Color.clear
            .frame(width: axis == .horizontal ? half : nil, height: axis == .vertical ? half : nil)
    }

    /// The fixed center playhead: a blue line across the track, perpendicular to the scroll axis.
    /// The fixed center playhead: a blue line across the track, perpendicular to the scroll axis.
    private var playhead: some View {
        GeometryReader { geo in
            Path { path in
                if axis == .vertical {
                    let midY = geo.size.height / 2
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: geo.size.width, y: midY))
                } else {
                    let midX = geo.size.width / 2
                    path.move(to: CGPoint(x: midX, y: 0))
                    path.addLine(to: CGPoint(x: midX, y: geo.size.height))
                }
            }
            .stroke(.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .allowsHitTesting(false)
    }

    /// Horizontal (bottom card) only — the vertical card drops the legend to give the histogram the
    /// full card height; its colors read directly off the bars.
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

/// Time readout, isolated so only it re-renders as the clock moves while scrubbing. Horizontal (the
/// bottom card) stacks the date over a large H:MM; vertical (the slim landscape card) drops the date
/// and trails smaller seconds after the time.
private struct TimelineClockLabel: View {
    @Environment(\.calendar) private var calendar
    let clock: ScrubClock
    let axis: Axis

    var body: some View {
        switch axis {
        case .horizontal:
            VStack(alignment: .leading, spacing: 0) {
                Text(clock.instant, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(clock.instant, format: .dateTime.hour().minute())
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        case .vertical:
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(clock.instant, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(verbatim: secondsLabel)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var secondsLabel: String {
        let second = calendar.component(.second, from: clock.instant)
        return second < 10 ? ":0\(second)" : ":\(second)"
    }
}

private struct HistogramTrack: View {
    // The calendar/time zone the hour labels are computed in. Resolves to the user's current
    // calendar in the app; tests pin it so snapshots render identically on any machine.
    @Environment(\.calendar) private var calendar
    let axis: Axis
    let span: TimeRange
    let timeline: DayTimeline
    let length: CGFloat

    var body: some View {
        // Capture the environment value here — the Canvas draw closure runs after `body` returns.
        let calendar = calendar
        return Canvas { context, size in
            let duration = span.end.timeIntervalSince(span.start)
            guard duration > 0 else { return }
            let isVertical = axis == .vertical
            // The gutter holding the time labels: along the top (horizontal) or the left (vertical,
            // where a horizontal "06:00" needs more room than a stacked one).
            let labelArea: CGFloat = isVertical ? 30 : 13
            let timeExtent = isVertical ? size.height : size.width
            func pos(_ time: Date) -> CGFloat {
                // Vertical runs now→past, top→bottom (so scrolling up reveals older); horizontal runs start→end.
                let fraction = isVertical
                    ? span.end.timeIntervalSince(time) / duration
                    : time.timeIntervalSince(span.start) / duration
                return CGFloat(fraction) * timeExtent
            }

            drawGaps(in: context, size: size, isVertical: isVertical, pos: pos)
            drawHourLabels(in: context, size: size, isVertical: isVertical, pos: pos, calendar: calendar)

            let barWidth: CGFloat = 3
            let maxBarLength = (isVertical ? size.width : size.height) - labelArea
            for bucket in timeline.motion where bucket.intensity > 0 {
                let barLength = Swift.max(barWidth, maxBarLength * CGFloat(bucket.intensity) / 100)
                let p = pos(bucket.time)
                // Horizontal: bars rise from the bottom. Vertical: bars grow rightward from the left gutter.
                let rect = isVertical
                    ? CGRect(x: labelArea, y: p - barWidth / 2, width: barLength, height: barWidth)
                    : CGRect(x: p - barWidth / 2, y: size.height - barLength, width: barWidth, height: barLength)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color(at: bucket.time).opacity(0.9)))
            }
        }
        // Horizontal: fixed `length` wide, height from the 68pt strip. Vertical: `length` tall, the
        // Canvas filling the card's width (so bars have room to grow rightward).
        .frame(width: axis == .horizontal ? length : nil, height: axis == .vertical ? length : nil)
    }

    /// No-footage ranges drawn as a diagonal hatch — distinct from "recorded but no motion".
    /// Spans the full cross-axis: a vertical strip (horizontal track) or a horizontal band (vertical).
    private func drawGaps(in context: GraphicsContext, size: CGSize, isVertical: Bool, pos: (Date) -> CGFloat) {
        for gap in timeline.gaps {
            let start = pos(gap.range.start)
            let end = Swift.max(start + 1, pos(gap.range.end))
            let rect = isVertical
                ? CGRect(x: 0, y: start, width: size.width, height: end - start)
                : CGRect(x: start, y: 0, width: end - start, height: size.height)
            context.fill(Path(rect), with: .color(.gray.opacity(0.08)))
            context.drawLayer { layer in
                layer.clip(to: Path(rect))
                // 45° lines: run length equals the band height so the slope stays diagonal in both axes.
                let run = rect.height
                var hatch = Path()
                var origin = rect.minX - run
                while origin < rect.maxX {
                    hatch.move(to: CGPoint(x: origin, y: rect.maxY))
                    hatch.addLine(to: CGPoint(x: origin + run, y: rect.minY))
                    origin += 7
                }
                layer.stroke(hatch, with: .color(.gray.opacity(0.3)), lineWidth: 1)
            }
        }
    }

    /// Faint time labels every 6h in the gutter, leaving the bars flush to the opposite edge.
    private func drawHourLabels(in context: GraphicsContext, size: CGSize, isVertical: Bool, pos: (Date) -> CGFloat, calendar: Calendar) {
        guard var tick = calendar.nextDate(
            after: span.start, matching: DateComponents(minute: 0), matchingPolicy: .nextTime
        ) else { return }
        while tick < span.end {
            let hour = calendar.component(.hour, from: tick)
            if hour.isMultiple(of: 6) {
                let point = isVertical ? CGPoint(x: 16, y: pos(tick)) : CGPoint(x: pos(tick), y: 7)
                // Vertical: a compact 24-hour tick (00/06/12/18) in the left gutter; horizontal keeps H:MM.
                let label = isVertical
                    ? Text(verbatim: hour < 10 ? "0\(hour)" : "\(hour)")
                    : Text(tick, format: .dateTime.hour().minute())
                context.draw(
                    label.font(.system(size: 9)).foregroundStyle(.tertiary),
                    at: point,
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

/// How densely the timeline is drawn — the zoom pill cycles through these. The same scale drives
/// both axes so the bar spacing reads identically whether the card is horizontal or vertical.
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

    var icon: String {
        switch self {
        case .hour: "clock"
        case .day: "sun.max"
        case .week: "calendar"
        }
    }

    var next: TimelineZoom {
        let all = Self.allCases
        return all[(all.firstIndex(of: self).map { $0 + 1 } ?? 0) % all.count]
    }
}
