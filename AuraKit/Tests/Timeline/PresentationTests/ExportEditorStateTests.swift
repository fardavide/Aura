import Foundation
import Testing

import ExportsDomain
import TimelineDomain
@testable import TimelinePresentation

/// The dead-control audit, as assertions. Every control this screen carries has exactly one of
/// four fates — working, absent, disabled with its reason, or enabled and saying the thing behind
/// it is not built — and these tests are where that is actually enforced.
struct ExportEditorControlTests {

    @Test func `given a selection over footage then create is offered`() {
        let sut = editing()
        #expect(sut.canCreate)
        #expect(sut.createDisabledReason == nil)
    }

    @Test func `given a selection holding no recorded second then create is disabled with its reason`() {
        let sut = editing(gaps: [gap(0, 9_999)])
        #expect(!sut.canCreate)
        #expect(sut.createDisabledReason == "No recording anywhere in this range — move a handle onto footage")
    }

    /// Absent, not disabled: the create button's reason already states the fact once, and two
    /// greyed controls side by side is two unanswerable questions where one sentence will do.
    @Test func `given no recorded second then play selection is absent rather than disabled`() {
        #expect(!editing(gaps: [gap(0, 9_999)]).showsPlaySelection)
        #expect(editing().showsPlaySelection)
    }

    @Test func `given the request is in flight then create and cancel are both gone`() {
        let sut = editing().phased(.creating)
        #expect(!sut.showsCreate)
        #expect(!sut.showsCancel)
    }

    /// The request belongs to the server from the moment it is accepted; a Cancel that cannot
    /// recall it would lie about what it cancels.
    @Test func `given the server is cutting then cancel is gone and view in exports is offered`() {
        let sut = editing().phased(.processing(ExportId("e1")))
        #expect(!sut.showsCancel)
        #expect(sut.showsViewInExports)
    }

    @Test func `given a transport failure then a retry is offered`() {
        let sut = editing().phased(.failed(.unreachable))
        #expect(sut.showsRetry)
    }

    /// The one place a control is removed rather than disabled: pressing it could only fail the
    /// same way, so the caption asks for the only thing that can change the outcome.
    @Test func `given the server refused the range then no retry is offered at all`() {
        let sut = editing().phased(.failed(.rejected))
        #expect(!sut.showsRetry)
        #expect(sut.failureHint == "Move a handle to try a different range")
    }

    @Test func `given a coarse rung then the handles are withdrawn and the zoom hint appears`() {
        #expect(!editing(zoom: .day).showsHandles)
        #expect(!editing(zoom: .week).showsHandles)
        #expect(editing(zoom: .day).showsZoomToAdjust)
        #expect(editing(zoom: .minute).showsHandles)
        #expect(editing(zoom: .hour).showsHandles)
        #expect(!editing(zoom: .minute).showsZoomToAdjust)
    }

    @Test func `given a committed request then the handles stop being interactive`() {
        #expect(!editing().phased(.creating).handlesAreInteractive)
        #expect(!editing().phased(.processing(ExportId("e1"))).handlesAreInteractive)
        #expect(editing().handlesAreInteractive)
    }

    /// Absent at entry by construction — the seed is built around the playhead — and appearing the
    /// moment scrubbing takes the playhead outside.
    @Test func `given the playhead inside the clip then reset to playhead is absent`() {
        #expect(!editing(playhead: at(1_020)).showsResetToPlayhead)
        #expect(editing(playhead: at(5_000)).showsResetToPlayhead)
    }
}

struct ExportEditorNoticeTests {

    @Test func `given a clip over ten minutes then the advisory names the length in the button`() {
        let sut = editing(selection: ExportSelection(start: at(0), end: at(1_440)))
        #expect(sut.createTitle == "Create 24:00 clip")
        #expect(sut.longClipAdvisory == "Long clips take the server a while to cut")
    }

    @Test func `given a clip under ten minutes then the button is plain and there is no advisory`() {
        let sut = editing()
        #expect(sut.createTitle == "Create Export")
        #expect(sut.longClipAdvisory == nil)
    }

    /// Spanning a gap is valid — the server exports the footage that exists — so this is a notice,
    /// not an error, and create stays enabled.
    @Test func `given a clip spanning a gap then the missing seconds are stated and create stays live`() {
        let sut = editing(selection: ExportSelection(start: at(1_000), end: at(1_090)), gaps: [gap(1_020, 1_052)])
        #expect(sut.gapNotice == "Includes 0:32 with no recording")
        #expect(sut.canCreate)
    }

    @Test func `given a clip clear of any gap then there is no notice`() {
        #expect(editing().gapNotice == nil)
    }
}

// MARK: - helpers

private func editing(
    selection: ExportSelection = ExportSelection(start: at(1_000), end: at(1_090)),
    playhead: Date = at(1_020),
    zoom: TimelineZoom = .minute,
    gaps: [FootageGap] = []
) -> ExportEditorState {
    ExportEditorState(
        selection: selection,
        span: TimeRange(start: at(0), end: at(10_000)),
        playhead: playhead,
        zoom: zoom,
        gaps: gaps,
        phase: .editing
    )
}

private extension ExportEditorState {
    func phased(_ phase: ExportEditorPhase) -> ExportEditorState {
        ExportEditorState(selection: selection, span: span, playhead: playhead, zoom: zoom, gaps: gaps, phase: phase)
    }
}

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
private func gap(_ start: TimeInterval, _ end: TimeInterval) -> FootageGap {
    FootageGap(range: TimeRange(start: at(start), end: at(end)))
}
