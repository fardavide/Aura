import SwiftUI
import Testing

import CamerasEntities
import ExportsDomain
import TestDoubles
import TimelineDomain
import TimelinePresentation

/// Screenshot tests for the export range editor, over the same black placeholder the rest of the
/// Timeline-detail suite uses. Driven by literal state, so no player, no server and no gestures.
///
/// What these actually guard is the dead-control audit. `ExportEditorStateTests` proves the state
/// says a control is absent; these prove the panel then does not draw it — and that the panel
/// growing to say why never reaches the camera slot, which the `detail-areas` highlight baseline
/// in the sibling suite checks explicitly.
///
/// The entry transition, the clamp rubber-band and the precision expansion are deliberately not
/// here: they are timing, and a still frame of a spring tests nothing.
@MainActor
struct ExportEditorSnapshotTests {

    @Test func `given export mode at rest then the handles and readout read`() {
        assertScreenSnapshot(exportDetail(editor()), named: "export-editing")
    }

    @Test func `given a clip spanning a gap then the missing seconds are stated`() {
        let editing = editor(
            selection: ExportSelection(start: gapStart.addingTimeInterval(-40), end: gapStart.addingTimeInterval(70)),
            timeline: gappyTimelineFixture()
        )
        assertScreenSnapshot(exportDetail(editing, timeline: gappyTimelineFixture()), named: "export-gap")
    }

    @Test func `given a clip with no footage in it then create is disabled with its reason`() {
        let editing = editor(
            selection: ExportSelection(start: gapStart.addingTimeInterval(20), end: gapStart.addingTimeInterval(80)),
            timeline: gappyTimelineFixture()
        )
        assertScreenSnapshot(exportDetail(editing, timeline: gappyTimelineFixture()), named: "export-invalid")
    }

    @Test func `given a clip over ten minutes then the button names its length`() {
        let editing = editor(
            selection: ExportSelection(start: exportAnchor, end: exportAnchor.addingTimeInterval(1_440))
        )
        assertScreenSnapshot(exportDetail(editing), named: "export-long")
    }

    @Test func `given a coarse rung then the handles are withdrawn and the zoom hint shows`() {
        assertScreenSnapshot(exportDetail(editor(zoom: .day), zoom: .day), named: "export-coarse")
    }

    @Test func `given the selection playing then the region reads as the progress`() {
        assertScreenSnapshot(
            exportDetail(editor(), isPlayingSelection: true),
            named: "export-playing"
        )
    }

    @Test func `given the server cutting then the strip replaces the actions`() {
        assertScreenSnapshot(
            exportDetail(editor(phase: .processing(ExportId("e1")))),
            named: "export-processing"
        )
    }

    @Test func `given a transport failure then a retry is offered`() {
        assertScreenSnapshot(exportDetail(editor(phase: .failed(.unreachable))), named: "export-failed")
    }

    /// The one state where a control is removed rather than dimmed — worth a baseline of its own,
    /// because "there is no Try again here" is exactly the kind of absence a refactor restores.
    @Test func `given a server rejection then there is no retry at all`() {
        assertScreenSnapshot(exportDetail(editor(phase: .failed(.rejected))), named: "export-rejected")
    }

    @Test func `given a finished clip then play and done are offered`() {
        assertScreenSnapshot(exportDetail(editor(phase: .ready(readyExport))), named: "export-ready")
    }
}

// MARK: - fixtures

/// Inside the rich fixture's busy stretch, so the dimmed-outside treatment has motion and markers
/// to act on rather than an empty track.
private let exportAnchor = snapshotSpanStart.addingTimeInterval(33.4 * 3_600)
private let gapStart = snapshotSpanStart.addingTimeInterval(20 * 3_600)

private let readyExport = Export(
    id: ExportId("e1"),
    camera: CameraName("driveway"),
    name: "driveway_20260918_143012",
    createdAt: exportAnchor,
    isProcessing: false,
    videoPath: "/media/frigate/exports/e1.mp4",
    thumbnailPath: nil
)

private func editor(
    selection: ExportSelection = ExportSelection(
        start: exportAnchor.addingTimeInterval(-30),
        end: exportAnchor.addingTimeInterval(60)
    ),
    zoom: TimelineZoom = .minute,
    timeline: DayTimeline = richTimelineFixture(),
    phase: ExportEditorPhase = .editing
) -> ExportEditorState {
    ExportEditorState(
        selection: selection,
        span: TimeRange(start: snapshotSpanStart, end: snapshotNow),
        playhead: exportAnchor,
        zoom: zoom,
        gaps: timeline.gaps,
        phase: phase
    )
}

@MainActor
private func exportDetail(
    _ editor: ExportEditorState,
    zoom: TimelineZoom = .minute,
    timeline: DayTimeline = richTimelineFixture(),
    isPlayingSelection: Bool = false
) -> some View {
    recordingDetailScreen(
        state: RecordingDetailState(
            cameraName: "Driveway",
            instant: exportAnchor,
            span: TimeRange(start: snapshotSpanStart, end: snapshotNow),
            dayTimeline: timeline,
            zoom: zoom,
            isPlaying: false,
            speed: .oneX,
            slot: .footage,
            isLive: false,
            isPlayable: true,
            export: editor,
            isPlayingSelection: isPlayingSelection
        )
    ) {
        Color.black
    }
}
