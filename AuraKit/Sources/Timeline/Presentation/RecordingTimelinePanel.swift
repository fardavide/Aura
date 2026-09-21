import Foundation
import SwiftUI

import CommonDesign

/// The panel that carries the whole time axis: the day the playhead is in, the clock, the zoom,
/// the day-overview bar, the scrub track with its ruler, and the transport.
///
/// One set of parts in three arrangements — what changes between a phone, a phone on its side and a
/// big window is the panel, not the controls it holds. The glass, rim and glow are the enclosing
/// `auroraSheet` — this only lays out its content (tokens §4: one glass layer per surface).
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
    private static let controlsWidth: CGFloat = 300
    private static let splitPanelMaxWidth: CGFloat = 1_100

    var body: some View {
        content
            .padding(arrangement == .rail ? 12 : 16)
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
            goLive: { interruptGlide(); actions.goLive() },
            // Opening the editor settles any glide first: the seed is built around the playhead,
            // and a playhead still sliding would seed a clip around a moment already gone.
            beginExport: { interruptGlide(); actions.beginExport() },
            cancelExport: actions.cancelExport,
            changeSelection: actions.changeSelection,
            resetSelectionToPlayhead: { interruptGlide(); actions.resetSelectionToPlayhead() },
            playSelection: { interruptGlide(); actions.playSelection() },
            createExport: actions.createExport,
            viewInExports: actions.viewInExports,
            playExport: actions.playExport,
            finishExport: actions.finishExport
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
                VStack(alignment: .leading, spacing: 3) {
                    // The stepper gets a row to itself: with four zoom rungs it and the picker
                    // no longer fit one line on a 393pt phone, and sharing truncated the day to
                    // "SUN,…" — the one thing the control exists to tell you.
                    //
                    // In export mode it is withdrawn entirely, for the same reason the
                    // day-overview bar is: stepping a whole day while cutting a 90-second clip
                    // would leave the selection behind and the playhead somewhere else.
                    if !state.isExporting {
                        dayStepper
                    }
                    HStack(alignment: .bottom) {
                        clock
                        Spacer(minLength: 8)
                        zoomPicker(spellsOutLabels: false)
                    }
                }
                // The day bar is withdrawn while a clip is being cut and the readout takes its
                // row: a day-scale fling is not something to leave under a thumb doing
                // second-scale work, and the swap keeps the panel the same height.
                if let export = state.export {
                    readout(export, isNarrow: false)
                } else {
                    dayOverview
                }
                horizontalTrack
                footer(density: .compact, isStacked: true)
            }
        case .rail:
            VStack(spacing: 10) {
                clock
                if let export = state.export {
                    readout(export, isNarrow: true)
                } else {
                    dayLabel
                }
                zoomChip
                verticalAxis
                footer(density: .narrow, isStacked: false)
            }
        case .split:
            HStack(alignment: .top, spacing: 20) {
                // Wide enough for both, and a pointer does not fling a day bar by accident — so
                // this is the one arrangement that keeps the overview in export mode.
                horizontalAxis
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 12) {
                    clock
                    if let export = state.export {
                        readout(export, isNarrow: true)
                    } else {
                        dayStepper
                    }
                    zoomPicker(spellsOutLabels: true)
                    footer(density: .wide, isStacked: false)
                }
                .frame(width: Self.controlsWidth)
            }
            .frame(maxWidth: Self.splitPanelMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

    /// The transport, or what replaces it once a clip is being cut.
    @ViewBuilder private func footer(density: RecordingTransportBar.Density, isStacked: Bool) -> some View {
        if let export = state.export {
            VStack(alignment: .leading, spacing: 10) {
                if export.isEditing {
                    ExportActionRow(
                        state: export,
                        isPlayingSelection: state.isPlayingSelection,
                        isStacked: isStacked,
                        onCancel: coordinated.cancelExport,
                        onPlaySelection: coordinated.playSelection,
                        onCreate: coordinated.createExport
                    )
                }
                ExportLifecycleStrip(
                    phase: export.phase,
                    showsRetry: export.showsRetry,
                    failureHint: export.failureHint,
                    onRetry: coordinated.createExport,
                    onViewInExports: coordinated.viewInExports,
                    onPlay: coordinated.playExport,
                    onDone: coordinated.finishExport
                )
                if export.showsZoomToAdjust {
                    zoomToAdjustChip
                }
            }
            .transition(.opacity)
        } else {
            RecordingTransportBar(state: state, actions: coordinated, density: density)
        }
    }

    private func readout(_ export: ExportEditorState, isNarrow: Bool) -> some View {
        ExportReadoutRow(
            state: export,
            isNarrow: isNarrow,
            onResetToPlayhead: coordinated.resetSelectionToPlayhead
        )
    }

    /// A control, not a caption — it is phrased as an instruction and it does the thing.
    private var zoomToAdjustChip: some View {
        HStack(spacing: 7) {
            Button {
                coordinated.selectZoom(.minute)
            } label: {
                Label("Zoom in to adjust", systemImage: "plus.magnifyingglass")
                    .auroraBadge(.neutral)
            }
            .buttonStyle(TransportBadgeButtonStyle())
            Text("Handles need Minute or Hour")
                .auroraText(.caption)
                .foregroundStyle(.auroraTextTertiary)
            Spacer(minLength: 0)
        }
    }

    /// The stacked arrangement's axis without the day bar above it — the bar is a sibling row
    /// there, so export mode can swap it out on its own.
    private var horizontalTrack: some View {
        RecordingScrubTrack(
            axis: .horizontal,
            state: state,
            actions: coordinated,
            filmstrip: filmstrip,
            thickness: Self.trackThickness,
            flingTask: $flingTask
        )
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

    /// `‹ SUN, JAN 11 ›` — the day the playhead is in, and a step either side of it. Disabled at
    /// either end of the span — `stepDay` clamps there (`RecordingPlayerViewModel.seek(to:)`), and
    /// `›` at the live edge is the state this screen opens in when pushed from the live camera, not
    /// an edge case (Dead-control audit).
    private var dayStepper: some View {
        let canStepBack = state.instant > state.span.start
        let canStepForward = state.instant < state.span.end
        return HStack(spacing: 6) {
            Button { coordinated.stepDay(-1) } label: { Image(systemName: "chevron.left") }
                .frame(width: 16, height: 16)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .disabled(!canStepBack)
                .opacity(canStepBack ? 1 : 0.45)
                .accessibilityLabel("Previous day")
            dayLabel
            Button { coordinated.stepDay(1) } label: { Image(systemName: "chevron.right") }
                .frame(width: 16, height: 16)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .disabled(!canStepForward)
                .opacity(canStepForward ? 1 : 0.45)
                .accessibilityLabel("Next day")
        }
        .auroraText(.overline)
        .buttonStyle(.plain)
        .foregroundStyle(.auroraTextSecondary)
    }

    private var dayLabel: some View {
        Text(state.instant, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
            .auroraText(.overline)
            .textCase(.uppercase)
            .foregroundStyle(.auroraTextSecondary)
            .lineLimit(1)
    }

    /// The big readout — hours and minutes, with the exact second trailing small and quiet, the
    /// same shape the tab's landscape readout uses. The AM/PM marker is dropped rather than
    /// trailed after the seconds, where it would read as part of them.
    private var clock: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1) {
            Text(state.instant, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                .auroraNumerals(.clockDetail)
            Text(verbatim: secondsSuffix)
                .auroraNumerals(.clockDetailSeconds)
                .foregroundStyle(.auroraTextSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var secondsSuffix: String {
        let second = calendar.component(.second, from: state.instant)
        return second < 10 ? ":0\(second)" : ":\(second)"
    }

    /// R3/R16: the flat `.well` container avoids nesting a second `glassEffect` inside the sheet's
    /// own, and the full brand gradient (not the violet→pink badge gradient) is what the mock uses
    /// for a control that is itself the screen's primary action.
    /// Four rungs do not fit a 393pt phone at full width — `Minute` wraps mid-word — so the
    /// stacked header takes the abbreviated labels and only `split`'s 300pt column spells them
    /// out. The abbreviation is `Minute`'s alone; the other three are already short.
    private func zoomPicker(spellsOutLabels: Bool) -> some View {
        AuroraSegmentedControl(
            options: TimelineZoom.allCases,
            selection: Binding(get: { state.zoom }, set: coordinated.selectZoom),
            container: .well,
            selectedFill: .diagonal
        ) { spellsOutLabels ? $0.title : $0.compactTitle }
    }

    /// The rail has no room for the ladder — one chip cycling the same three densities.
    private var zoomChip: some View {
        Button {
            coordinated.selectZoom(state.zoom.next)
        } label: {
            Label(state.zoom.compactTitle, systemImage: state.zoom.icon)
                .frame(maxWidth: .infinity)
                .auroraBadge(.neutral)
        }
        .buttonStyle(.plain)
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
