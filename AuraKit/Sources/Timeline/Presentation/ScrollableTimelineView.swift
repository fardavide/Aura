import Foundation
import SwiftUI

import CommonDesign
import TimelineDomain

/// The scrubber card: a time header, a scrollable activity **histogram** with a fixed center
/// playhead, and the transport. Drawn in the shared `TimelineTrackStyle` language (intensity-
/// coloured motion, gradient/amber marker pills in their own lane, hatched gaps), so this track,
/// the detail's and the day bar read as one design. Scrolling/panning the histogram sets the scrub
/// time.
///
/// Laid out per `arrangement` — `.stack` (a wide card flush to the bottom), `.row` (a single-row
/// card, iPad/macOS) or `.rail` (a tall card flush to the trailing edge, iPhone landscape). Time
/// always reads start→end along the scroll axis — left→right when horizontal, top→bottom when
/// vertical — with the newest end anchored under the playhead.
///
/// The card also carries the transport, and playback scrolls the histogram rather than moving the
/// playhead: the playhead is fixed at the centre by design, so "the clock advanced" and "the track
/// slid past" are the same thing.
struct ScrollableTimelineView: View {
    let arrangement: TimelineCardArrangement
    let span: TimeRange
    let timeline: DayTimeline
    let clock: ScrubClock
    let transport: TimelineTransport
    let onScrub: (Date) -> Void

    // Opens at the finest preset, matching the per-camera timeline: the track is anchored at the
    // live edge, so what a screen entry is about is the last stretch of footage — at day density
    // that is a few points wide. The pill and the pinch still reach day and week.
    @State private var pointsPerHour: CGFloat = TimelineZoom.hour.pointsPerHour
    @GestureState private var pinchBaseline: CGFloat?
    @State private var scrollPosition = ScrollPosition()
    @State private var histogramViewport: CGFloat = 0

    var body: some View {
        glassCard
            .auroraSheet(edge: arrangement.sheetEdge, showsGrabber: false)
    }

    @ViewBuilder private var glassCard: some View {
        switch arrangement {
        case .rail:
            // Measure the available space and size the content to it explicitly: `maxHeight:
            // .infinity` does not survive `glassEffect` on-device (the glass hugs the header), so
            // the histogram would collapse. A definite frame from a GeometryReader makes the card
            // span the full height.
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 12) {
                    header
                    histogram
                    TimelineTransportControls(arrangement: .rail, transport: transport)
                }
                .padding(16)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
        case .stack:
            VStack(alignment: .leading, spacing: 12) {
                header
                histogram
                TimelineTransportControls(arrangement: .stack, transport: transport)
            }
            .padding(16)
            // No safe-area clearance here: `.auroraSheet(edge:)` (below, in `body`) already
            // ignores the container safe area so the card sits flush behind the floating tab
            // bar per decision #5 — padding for it here would double-reserve the same space and
            // push the visible card up, leaving a gap between it and the bar.
        case .row:
            HStack(spacing: 24) {
                TimelineClockLabel(clock: clock, arrangement: .row).frame(width: 190, alignment: .leading)
                histogram
                VStack(spacing: 10) {
                    TimelineTransportControls(arrangement: .row, transport: transport)
                    zoomButton
                }
            }
            .padding(.init(top: 18, leading: 32, bottom: 24, trailing: 32))
            // No safe-area clearance here either — see the `.stack` case above.
        }
    }

    @ViewBuilder private var header: some View {
        switch arrangement {
        case .rail:
            // The slim card stacks the readout over the zoom pill (no room for them side by side).
            VStack(alignment: .leading, spacing: 10) {
                TimelineClockLabel(clock: clock, arrangement: .rail)
                zoomButton
            }
        case .stack:
            HStack(alignment: .firstTextBaseline) {
                TimelineClockLabel(clock: clock, arrangement: .stack)
                Spacer()
                zoomButton
            }
        // `.row` renders no header — the clock is its own fixed-width column and the zoom pill
        // moves into the transport column (see `glassCard`); this branch is never reached.
        case .row:
            EmptyView()
        }
    }

    /// One tap steps `zoomPreset.next` and re-anchors. Flat (not `.auroraChip`'s glass capsule):
    /// this pill sits **inside** `.auroraSheet`, and CommonDesign's `auroraChip(over:)` always
    /// applies `glassEffect` — one glass layer per surface, so the flat capsule is spelled inline
    /// from the chip's own catalog tokens instead.
    private var zoomButton: some View {
        Button { zoom(to: zoomPreset.next.pointsPerHour) } label: {
            Text(zoomPreset.title)
                .auroraText(.chip)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.auroraChipFill, in: Capsule())
                .overlay { Capsule().strokeBorder(.auroraChipBorder, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private var histogram: some View {
        GeometryReader { geo in
            let isVertical = arrangement.axis == .vertical
            let viewport = isVertical ? geo.size.height : geo.size.width
            let scale = TimelineScale(axis: arrangement.axis, span: span, pointsPerHour: pointsPerHour, viewport: viewport)
            ScrollView(isVertical ? .vertical : .horizontal, showsIndicators: false) {
                scrollStack {
                    endSpacer(viewport / 2)
                    HistogramTrack(axis: arrangement.axis, span: span, timeline: timeline, length: scale.contentLength)
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
                    transport.endInteraction()
                // Our own re-anchoring while playing — not the user, so it must neither pause
                // playback nor block the auto-refresh.
                case .animating:
                    break
                // Pause auto-refresh while the user is panning so a tick can't yank the histogram,
                // and hand the playhead over: the drag and the transport would otherwise both be
                // driving the same clock. Playback the user was watching resumes on release.
                case .tracking, .interacting, .decelerating:
                    clock.beginScrub()
                    transport.beginInteraction()
                }
            }
            // Guard against isScrubbing — and a pending playback resume — getting stuck if the
            // view disappears mid-deceleration.
            .onDisappear {
                clock.endScrub()
                transport.endInteraction()
            }
            // Simultaneous so the pinch composes with the scroll pan instead of blocking it.
            .simultaneousGesture(magnify)
            .auroraTrackWell()
            .overlay(alignment: .center) {
                AuroraPlayhead(axis: arrangement.axis)
                    .padding(arrangement.axis == .horizontal ? .vertical : .horizontal, 3)
            }
        }
        // The zoom pill lives outside the GeometryReader — keep the measured viewport around for
        // its re-anchor math.
        .onGeometryChange(for: CGFloat.self) { proxy in
            arrangement.axis == .vertical ? proxy.size.height : proxy.size.width
        } action: { histogramViewport = $0 }
        // `.stack`/`.row`: a fixed strip (60 / 72pt). `.rail`: claim all the height the full-height
        // card leaves below the header, so the histogram (and the well) fill it.
        .frame(height: arrangement.histogramLength)
        .frame(maxHeight: arrangement.histogramLength == nil ? .infinity : nil)
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
        let scale = TimelineScale(axis: arrangement.axis, span: span, pointsPerHour: clamped, viewport: histogramViewport)
        if arrangement.axis == .vertical {
            scrollPosition.scrollTo(y: scale.offset(for: clock.instant))
        } else {
            scrollPosition.scrollTo(x: scale.offset(for: clock.instant))
        }
    }

    /// Lays the two padding spacers and the track along the scroll axis.
    @ViewBuilder
    private func scrollStack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if arrangement.axis == .vertical {
            VStack(spacing: 0, content: content)
        } else {
            HStack(spacing: 0, content: content)
        }
    }

    /// A half-viewport spacer so the track's start/end can reach the centered playhead.
    private func endSpacer(_ half: CGFloat) -> some View {
        Color.clear
            .frame(width: arrangement.axis == .horizontal ? half : nil, height: arrangement.axis == .vertical ? half : nil)
    }
}

/// Time readout, isolated so only it re-renders as the clock moves while scrubbing. `.stack`/`.row`
/// stack the day over a large `H:MM` with trailing seconds; `.rail` keeps a single line (no room for
/// the day, and the rail has read this way since 0.4.0).
private struct TimelineClockLabel: View {
    @Environment(\.calendar) private var calendar
    let clock: ScrubClock
    let arrangement: TimelineCardArrangement

    var body: some View {
        switch arrangement {
        case .stack, .row:
            VStack(alignment: .leading, spacing: 3) {
                Text(clock.instant, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .auroraText(.overline)
                    .textCase(.uppercase)
                    .foregroundStyle(.auroraTextSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    // AM/PM is dropped, not moved: the day line above already says which day it
                    // is, and a third `Text` would break this 34/16 baseline pair.
                    Text(clock.instant, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                        .auroraNumerals(.clockTab)
                    Text(verbatim: secondsLabel)
                        .auroraNumerals(.clockTabSeconds)
                        .foregroundStyle(.auroraTextSecondary)
                }
            }
        case .rail:
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(clock.instant, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .auroraNumerals(.clockTab)
                Text(verbatim: secondsLabel)
                    .auroraNumerals(.clockTabSeconds)
                    .foregroundStyle(.auroraTextSecondary)
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
            /// The band `[from, to]` covers along the time axis, whichever way this axis runs.
            func timeBand(from start: Date, to end: Date) -> (lo: CGFloat, hi: CGFloat) {
                let a = pos(start)
                let b = pos(end)
                return (Swift.min(a, b), Swift.max(a, b))
            }

            drawGaps(in: context, size: size, isVertical: isVertical, pos: pos)
            drawMidnightLines(in: context, size: size, isVertical: isVertical, pos: pos, calendar: calendar)
            drawHourLabels(in: context, size: size, isVertical: isVertical, pos: pos, calendar: calendar)

            // The lane sits against the label gutter; motion grows from the opposite edge, kept
            // clear of it — the same cross-axis order as the detail's scrub track.
            let laneStart = labelArea + TimelineTrackStyle.laneInset
            let maxBarLength = (isVertical ? size.width : size.height)
                - laneStart - TimelineTrackStyle.laneThickness - TimelineTrackStyle.laneClearance
            let bucketDuration = timeline.motionBucketDuration
            for bucket in timeline.motion where bucket.intensity > 0 {
                let band = timeBand(from: bucket.time, to: bucket.time.addingTimeInterval(bucketDuration))
                let barAcross = Swift.max(1, band.hi - band.lo - TimelineTrackStyle.motionBarSeparator)
                let barLength = Swift.max(2, maxBarLength * CGFloat(bucket.intensity) / 100)
                let rect = isVertical
                    ? CGRect(x: size.width - barLength, y: band.lo, width: barLength, height: barAcross)
                    : CGRect(x: band.lo, y: size.height - barLength, width: barAcross, height: barLength)
                context.fill(Path(rect), with: .color(TimelineTrackStyle.motionColor(intensity: bucket.intensity)))
            }

            for marker in timeline.markers {
                // An in-progress marker has no end yet; it runs to the live edge.
                let band = timeBand(from: marker.start, to: marker.end ?? span.end)
                let across = Swift.max(band.hi - band.lo, TimelineTrackStyle.minimumMarkerLength)
                let mid = (band.lo + band.hi) / 2
                let pill = isVertical
                    ? CGRect(x: laneStart, y: mid - across / 2, width: TimelineTrackStyle.laneThickness, height: across)
                    : CGRect(x: mid - across / 2, y: laneStart, width: across, height: TimelineTrackStyle.laneThickness)
                TimelineTrackStyle.fillMarkerPill(pill, severity: marker.severity, in: context)
            }
        }
        // Horizontal: fixed `length` wide, height from the strip's fixed height. Vertical: `length`
        // tall, the Canvas filling the card's width (so bars have room to grow rightward).
        .frame(width: axis == .horizontal ? length : nil, height: axis == .vertical ? length : nil)
    }

    /// No-footage ranges drawn with the shared hatch — distinct from "recorded but no motion".
    /// Spans the full cross-axis: a vertical strip (horizontal track) or a horizontal band (vertical).
    private func drawGaps(in context: GraphicsContext, size: CGSize, isVertical: Bool, pos: (Date) -> CGFloat) {
        for gap in timeline.gaps {
            // The vertical axis maps later instants to smaller offsets, so order the band before
            // enforcing the minimum — clamping against the raw start collapses it to a hairline.
            let a = pos(gap.range.start)
            let b = pos(gap.range.end)
            let lo = Swift.min(a, b)
            let hi = Swift.max(Swift.max(a, b), lo + 1)
            let rect = isVertical
                ? CGRect(x: 0, y: lo, width: size.width, height: hi - lo)
                : CGRect(x: lo, y: 0, width: hi - lo, height: size.height)
            TimelineHatch.fill(rect, in: context)
        }
    }

    /// A divider at every local midnight in the span — the fixed 24h axis the mock draws does not
    /// exist here (decision #3 keeps the scrolling strip), but a midnight still separates two real
    /// days, so it is drawn.
    private func drawMidnightLines(in context: GraphicsContext, size: CGSize, isVertical: Bool, pos: (Date) -> CGFloat, calendar: Calendar) {
        var midnight = calendar.startOfDay(for: span.start)
        while midnight < span.end {
            if midnight > span.start {
                var line = Path()
                if isVertical {
                    line.move(to: CGPoint(x: 0, y: pos(midnight)))
                    line.addLine(to: CGPoint(x: size.width, y: pos(midnight)))
                } else {
                    line.move(to: CGPoint(x: pos(midnight), y: 0))
                    line.addLine(to: CGPoint(x: pos(midnight), y: size.height))
                }
                context.stroke(line, with: AuroraTrack.midnight, lineWidth: AuroraTrack.midnightLineWidth)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: midnight) else { return }
            midnight = next
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
                    label.font(.auroraNumerals(.axisLabel)).foregroundStyle(.auroraTextTertiary),
                    at: point,
                    anchor: .center
                )
            }
            guard let next = calendar.date(byAdding: .hour, value: 1, to: tick) else { return }
            tick = next
        }
    }
}
