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
///
/// The card also carries the transport, and playback scrolls the histogram rather than moving the
/// playhead: the playhead is fixed at the centre by design, so "the clock advanced" and "the track
/// slid past" are the same thing.
struct ScrollableTimelineView: View {
    let axis: Axis
    let span: TimeRange
    let timeline: DayTimeline
    let clock: ScrubClock
    let transport: TimelineTransport
    let onScrub: (Date) -> Void

    @State private var pointsPerHour: CGFloat = TimelineZoom.day.pointsPerHour
    @GestureState private var pinchBaseline: CGFloat?
    @State private var scrollPosition = ScrollPosition()
    @State private var histogramViewport: CGFloat = 0

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
                    TimelineTransportControls(axis: .vertical, transport: transport)
                }
                .padding(16)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                header
                histogram
                TimelineTransportControls(axis: .horizontal, transport: transport)
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
                Button { zoom(to: zoomPreset.next.pointsPerHour) } label: {
                    Label(zoomPreset.title, systemImage: zoomPreset.icon)
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.glass)
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                TimelineClockLabel(clock: clock, axis: .horizontal)
                Spacer()
                Button(zoomPreset.title) { zoom(to: zoomPreset.next.pointsPerHour) }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.glass)
            }
        }
    }

    private var histogram: some View {
        GeometryReader { geo in
            let isVertical = axis == .vertical
            let viewport = isVertical ? geo.size.height : geo.size.width
            let scale = TimelineScale(axis: axis, span: span, pointsPerHour: pointsPerHour, viewport: viewport)
            ScrollView(isVertical ? .vertical : .horizontal, showsIndicators: false) {
                scrollStack {
                    endSpacer(viewport / 2)
                    HistogramTrack(axis: axis, span: span, timeline: timeline, length: scale.contentLength)
                    endSpacer(viewport / 2)
                }
            }
            .scrollPosition($scrollPosition)
            // Vertical anchors the live edge at the top and runs into the past downward, so scrolling
            // *up* reveals older footage. Horizontal anchors the live edge at the trailing edge.
            .defaultScrollAnchor(isVertical ? .top : .trailing)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                isVertical ? geometry.contentOffset.y : geometry.contentOffset.x
            } action: { _, offset in
                // While playing, the clock leads and the scroll follows it — reading the time back
                // out of the offset we just wrote would feed rounding error into the playhead.
                guard scale.contentLength > 0, !transport.isPlaying else { return }
                onScrub(scale.instant(atOffset: offset))
            }
            // Playback slides the track under the fixed playhead. Nothing to do while parked: the
            // scroll is then the thing driving the clock, not the other way round.
            .onChange(of: clock.instant) { _, instant in
                guard transport.isPlaying, scale.contentLength > 0 else { return }
                if isVertical {
                    scrollPosition.scrollTo(y: scale.offset(for: instant))
                } else {
                    scrollPosition.scrollTo(x: scale.offset(for: instant))
                }
            }
            .onScrollPhaseChange { _, phase in
                switch phase {
                case .idle:
                    clock.endScrub()
                // Our own re-anchoring while playing — not the user, so it must neither pause
                // playback nor block the auto-refresh.
                case .animating:
                    break
                // Pause auto-refresh while the user is panning so a tick can't yank the histogram,
                // and hand the playhead over: the drag and the transport would otherwise both be
                // driving the same clock.
                case .tracking, .interacting, .decelerating:
                    clock.beginScrub()
                    transport.pause()
                }
            }
            // Guard against isScrubbing getting stuck if the view disappears mid-deceleration.
            .onDisappear { clock.endScrub() }
            // Simultaneous so the pinch composes with the scroll pan instead of blocking it.
            .simultaneousGesture(magnify)
            .background(.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
            }
            .overlay(alignment: .center) { playhead }
        }
        // The zoom pill lives outside the GeometryReader — keep the measured viewport around for
        // its re-anchor math.
        .onGeometryChange(for: CGFloat.self) { proxy in
            axis == .vertical ? proxy.size.height : proxy.size.width
        } action: { histogramViewport = $0 }
        // Horizontal: a fixed 68pt strip (as the bottom card). Vertical: claim all the height the
        // full-height card leaves below the header, so the histogram (and the glass) fill it.
        .frame(height: axis == .horizontal ? 68 : nil)
        .frame(maxHeight: axis == .vertical ? .infinity : nil)
    }

    /// The preset the pill shows — after a pinch, the one nearest the continuous density.
    private var zoomPreset: TimelineZoom {
        TimelineZoom.nearest(to: pointsPerHour)
    }

    /// Continuous pinch zoom — trackpad magnify on macOS, two-finger pinch on iOS — scaling the
    /// density from where it sat when the pinch began. The baseline lives in `@GestureState` so a
    /// *cancelled* gesture (app deactivation, a sheet reclaiming the touches) resets it too — a
    /// plain `@State` cleared in `onEnded` survives cancellation, snapping the next pinch back to
    /// a stale density.
    private var magnify: some Gesture {
        MagnifyGesture()
            .updating($pinchBaseline) { _, baseline, _ in
                if baseline == nil { baseline = pointsPerHour }
            }
            .onChanged { value in
                guard let baseline = pinchBaseline else { return }
                zoom(to: baseline * value.magnification)
            }
    }

    /// Applies a new density and re-anchors the scroll so the instant under the playhead stays
    /// put — the scroll offset is otherwise kept, which would re-read as a different time and
    /// yank the scrub position.
    private func zoom(to density: CGFloat) {
        let clamped = TimelineZoom.clamped(density)
        guard clamped != pointsPerHour else { return }
        pointsPerHour = clamped
        let scale = TimelineScale(axis: axis, span: span, pointsPerHour: clamped, viewport: histogramViewport)
        if axis == .vertical {
            scrollPosition.scrollTo(y: scale.offset(for: clock.instant))
        } else {
            scrollPosition.scrollTo(x: scale.offset(for: clock.instant))
        }
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
