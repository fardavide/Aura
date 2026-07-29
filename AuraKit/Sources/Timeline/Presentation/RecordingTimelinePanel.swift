import Foundation
import SwiftUI

/// The Liquid-Glass panel that carries the whole time axis: the day the playhead is in, the clock,
/// the zoom, the day-overview bar, the scrub track with its ruler, and the transport.
///
/// One set of parts in three arrangements — what changes between a phone, a phone on its side and a
/// big window is the panel, not the controls it holds.
struct RecordingTimelinePanel: View {
    enum Arrangement {
        /// A card across the bottom of a phone held upright.
        case stacked
        /// A tall rail down the trailing edge of a phone on its side, everything vertical.
        case rail
        /// A wide card under the hero: the time axis on the left, the controls on the right.
        case split
    }

    let arrangement: Arrangement
    let state: RecordingDetailState
    let actions: RecordingDetailActions

    @Environment(\.calendar) private var calendar

    private static let trackThickness: CGFloat = 72
    private static let railTrackThickness: CGFloat = 50
    private static let controlsWidth: CGFloat = 260

    var body: some View {
        content
            .padding(arrangement == .rail ? 12 : 16)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        switch arrangement {
        case .stacked:
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        dayStepper
                        clock(size: 30)
                    }
                    Spacer(minLength: 8)
                    zoomPicker
                }
                horizontalAxis
                RecordingTransportBar(state: state, actions: actions, density: .compact)
            }
        case .rail:
            VStack(spacing: 10) {
                clock(size: 22)
                dayLabel
                zoomChip
                verticalAxis
                RecordingTransportBar(state: state, actions: actions, density: .narrow)
            }
        case .split:
            HStack(alignment: .top, spacing: 20) {
                horizontalAxis
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 12) {
                    clock(size: 34)
                    dayStepper
                    zoomPicker
                    RecordingTransportBar(state: state, actions: actions, density: .wide)
                }
                .frame(width: Self.controlsWidth)
            }
        }
    }

    /// The day bar over the scrub track. Both are exactly as wide as this column, and each reads
    /// that width itself, so they always draw against the same footage.
    private var horizontalAxis: some View {
        VStack(spacing: 12) {
            dayOverview
            RecordingScrubTrack(
                axis: .horizontal,
                state: state,
                actions: actions,
                thickness: Self.trackThickness
            )
        }
    }

    /// The rail drops the day bar — there is no width for 24 hours of it — and gives every spare
    /// point of height to the track instead.
    private var verticalAxis: some View {
        RecordingScrubTrack(
            axis: .vertical,
            state: state,
            actions: actions,
            thickness: Self.railTrackThickness
        )
        .frame(maxHeight: .infinity)
    }

    /// `‹ SUN, JAN 11 ›` — the day the playhead is in, and a step either side of it.
    private var dayStepper: some View {
        HStack(spacing: 5) {
            Button { actions.stepDay(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous day")
            dayLabel
            Button { actions.stepDay(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next day")
        }
        .font(.caption2.weight(.bold))
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private var dayLabel: some View {
        Text(state.instant, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// The big readout — hours and minutes, with the exact second trailing small and quiet, the
    /// same shape the tab's landscape readout uses. The AM/PM marker is dropped rather than
    /// trailed after the seconds, where it would read as part of them.
    private func clock(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(state.instant, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                .font(.system(size: size, weight: .bold, design: .rounded))
            Text(verbatim: secondsSuffix)
                .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var secondsSuffix: String {
        let second = calendar.component(.second, from: state.instant)
        return second < 10 ? ":0\(second)" : ":\(second)"
    }

    private var zoomPicker: some View {
        Picker("Zoom", selection: Binding(get: { state.zoom }, set: actions.selectZoom)) {
            ForEach(TimelineZoom.allCases, id: \.self) { zoom in
                Text(zoom.title).tag(zoom)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .font(.footnote.weight(.bold))
    }

    /// The rail has no room for the ladder — one chip cycling the same three densities.
    private var zoomChip: some View {
        Button {
            actions.selectZoom(state.zoom.next)
        } label: {
            Label(state.zoom.title, systemImage: state.zoom.icon)
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Zoom")
        .accessibilityValue(state.zoom.title)
    }

    private var dayOverview: some View {
        let day = state.day(in: calendar)
        return VStack(spacing: 4) {
            DayOverviewBar(
                overview: DayOverview.rolledUp(from: state.dayTimeline, day: day, calendar: calendar),
                instant: state.instant,
                zoom: state.zoom,
                liveEdge: state.span.end,
                onScrubBegin: actions.beginScrub,
                onScrub: actions.scrub,
                onScrubEnd: actions.endScrub
            )
            DayOverviewScale()
        }
    }
}
