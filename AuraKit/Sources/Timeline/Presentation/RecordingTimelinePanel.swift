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
    let filmstrip: RecordingFilmstripStore

    @Environment(\.calendar) private var calendar
    /// The scrub track's release glide. Owned here — above the track, the day bar and the
    /// transport — so any of them taking the playhead can stop it first.
    @State private var flingTask: Task<Void, Never>?

    private static let trackThickness: CGFloat = 72
    private static let railTrackThickness: CGFloat = 50
    private static let controlsWidth: CGFloat = 260

    var body: some View {
        content
            .padding(arrangement == .rail ? 12 : 16)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            // A glide outliving the panel (a rotation mid-glide) would leave the scrub session
            // open and playback stranded paused — settle it on the way out.
            .onDisappear { interruptGlide() }
    }

    /// The actions the panel's controls actually get: every playhead-moving verb first settles a
    /// glide still running — two drivers would otherwise fight over the playhead frame by frame.
    /// `beginScrub` only cancels, without settling: the new grab continues the same scrub session,
    /// which is what carries the resume-playback intent across a caught glide.
    private var coordinated: RecordingDetailActions {
        RecordingDetailActions(
            playPause: { interruptGlide(); actions.playPause() },
            skip: { interruptGlide(); actions.skip($0) },
            selectSpeed: actions.selectSpeed,
            selectZoom: actions.selectZoom,
            beginScrub: { cancelGlide(); actions.beginScrub() },
            scrub: actions.scrub,
            endScrub: actions.endScrub,
            seek: { interruptGlide(); actions.seek($0) },
            stepDay: { interruptGlide(); actions.stepDay($0) },
            previousMarker: { interruptGlide(); actions.previousMarker() },
            nextMarker: { interruptGlide(); actions.nextMarker() },
            goLive: { interruptGlide(); actions.goLive() }
        )
    }

    private func cancelGlide() {
        flingTask?.cancel()
        flingTask = nil
    }

    /// Stops a running glide and settles its scrub — the settle itself yields if a newer grab
    /// owns the playhead, so this can never resume playback under a live drag.
    private func interruptGlide() {
        guard flingTask != nil else { return }
        cancelGlide()
        actions.endScrub()
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
                RecordingTransportBar(state: state, actions: coordinated, density: .compact)
            }
        case .rail:
            VStack(spacing: 10) {
                clock(size: 22)
                dayLabel
                zoomChip
                verticalAxis
                RecordingTransportBar(state: state, actions: coordinated, density: .narrow)
            }
        case .split:
            HStack(alignment: .top, spacing: 20) {
                horizontalAxis
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 12) {
                    clock(size: 34)
                    dayStepper
                    zoomPicker
                    RecordingTransportBar(state: state, actions: coordinated, density: .wide)
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
                actions: coordinated,
                filmstrip: filmstrip,
                thickness: Self.trackThickness,
                flingTask: $flingTask
            )
        }
    }

    /// The rail drops the day bar — there is no width for 24 hours of it — and gives every spare
    /// point of height to the track instead.
    private var verticalAxis: some View {
        RecordingScrubTrack(
            axis: .vertical,
            state: state,
            actions: coordinated,
            filmstrip: filmstrip,
            thickness: Self.railTrackThickness,
            flingTask: $flingTask
        )
        .frame(maxHeight: .infinity)
    }

    /// `‹ SUN, JAN 11 ›` — the day the playhead is in, and a step either side of it.
    private var dayStepper: some View {
        HStack(spacing: 5) {
            Button { coordinated.stepDay(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous day")
            dayLabel
            Button { coordinated.stepDay(1) } label: { Image(systemName: "chevron.right") }
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
        Picker("Zoom", selection: Binding(get: { state.zoom }, set: coordinated.selectZoom)) {
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
            coordinated.selectZoom(state.zoom.next)
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
                onScrubBegin: coordinated.beginScrub,
                onScrub: coordinated.scrub,
                onScrubEnd: coordinated.endScrub
            )
            DayOverviewScale()
        }
    }
}
