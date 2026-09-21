import Foundation
import Testing

import CamerasDomain
import CamerasEntities
import ExportsDomain
import TestDoubles
import TimelineDomain
@testable import TimelinePresentation

/// The verbs behind the export module: opening it, moving the clip, submitting it, and what each
/// failure leaves on screen.
@MainActor
struct ExportEditorViewModelTests {

    @Test func `given a playhead when opening the editor then the clip is seeded around it`() {
        let sut = makeExportViewModel()

        sut.beginExport()

        #expect(sut.state.export?.selection == ExportSelection(start: at(4_970), end: at(5_060)))
    }

    /// At Hour the seed is twelve points wide, so opening the editor there would present a clip
    /// nobody could grab.
    @Test func `given the hour rung when opening the editor then the axis snaps to minute`() {
        let sut = makeExportViewModel()
        sut.select(TimelineZoom.hour)

        sut.beginExport()

        #expect(sut.state.zoom == .minute)
    }

    @Test func `given a coarse rung when opening the editor then the axis still snaps to minute`() {
        let sut = makeExportViewModel()
        sut.select(TimelineZoom.week)

        sut.beginExport()

        #expect(sut.state.zoom == .minute)
    }

    @Test func `given the editor open when cancelling then nothing is left behind`() {
        let sut = makeExportViewModel()
        sut.beginExport()

        sut.cancelExport()

        #expect(sut.state.export == nil)
        #expect(!sut.state.isExporting)
    }

    @Test func `given the playhead moved away when resetting then the clip returns around it`() {
        let sut = makeExportViewModel()
        sut.beginExport()
        sut.change(selection: ExportSelection(start: at(1_000), end: at(1_090)))

        sut.resetSelectionToPlayhead()

        #expect(sut.state.export?.selection == ExportSelection(start: at(4_970), end: at(5_060)))
    }

    @Test func `given a selection when creating then the server is asked for exactly it`() async {
        let exports = FakeExportsRepository(.success([]), createdId: .success(ExportId("e1")))
        let sut = makeExportViewModel(exports: exports)
        sut.beginExport()

        await sut.createExport()

        #expect(exports.creationRequests.count == 1)
        #expect(exports.creationRequests.first?.from == at(4_970))
        #expect(exports.creationRequests.first?.to == at(5_060))
        #expect(exports.creationRequests.first?.camera == CameraName("driveway"))
    }

    @Test func `given the server accepts then the panel reports it is cutting`() async {
        let exports = FakeExportsRepository(.success([]), createdId: .success(ExportId("e1")))
        let sut = makeExportViewModel(exports: exports)
        sut.beginExport()

        await sut.createExport()

        #expect(sut.state.export?.phase == .processing(ExportId("e1")))
        #expect(sut.state.export?.showsViewInExports == true)
    }

    @Test func `given the server cannot be reached then the failure offers a retry`() async {
        let exports = FakeExportsRepository(.success([]), createdId: .failure(.unreachable))
        let sut = makeExportViewModel(exports: exports)
        sut.beginExport()

        await sut.createExport()

        #expect(sut.state.export?.phase == .failed(.unreachable))
        #expect(sut.state.export?.showsRetry == true)
    }

    @Test func `given the server refuses the range then no retry is offered`() async {
        let exports = FakeExportsRepository(.success([]), createdId: .failure(.rejected))
        let sut = makeExportViewModel(exports: exports)
        sut.beginExport()

        await sut.createExport()

        #expect(sut.state.export?.showsRetry == false)
        #expect(sut.state.export?.failureHint == "Move a handle to try a different range")
    }

    /// The range the server refused no longer exists, so the failure it reported no longer
    /// describes anything on screen.
    @Test func `given a refused range when a handle moves then the failure clears`() async {
        let exports = FakeExportsRepository(.success([]), createdId: .failure(.rejected))
        let sut = makeExportViewModel(exports: exports)
        sut.beginExport()
        await sut.createExport()

        sut.change(selection: ExportSelection(start: at(4_000), end: at(4_100)))

        #expect(sut.state.export?.phase == .editing)
        #expect(sut.state.export?.canCreate == true)
    }

    @Test func `given a finished export when dismissing it then the panel returns to playback`() async {
        let exports = FakeExportsRepository(.success([]), createdId: .success(ExportId("e1")))
        let sut = makeExportViewModel(exports: exports)
        sut.beginExport()
        await sut.createExport()

        sut.finishExport()

        #expect(sut.state.export == nil)
    }
}

@MainActor
private func makeExportViewModel(
    exports: FakeExportsRepository = FakeExportsRepository(.success([]))
) -> RecordingPlayerViewModel {
    let previews = GetCameraPreviews(provider: FakeCameraPreviewProvider())
    let recordings = GetCameraRecordings(repository: FakeCameraRecordingsRepository(.success([])))
    let camera = Camera(name: CameraName("driveway"), friendlyName: "Driveway", isEnabled: true, streamNames: ["driveway"])
    return RecordingPlayerViewModel(
        camera: camera,
        recordings: recordings,
        getDayTimeline: GetDayTimeline(
            repository: FakeCameraDayTimelineRepository(.success(DayTimeline(markers: [], motion: [], gaps: [])))
        ),
        createExport: CreateExport(repository: exports),
        getExport: GetExport(repository: exports),
        filmstrip: RecordingFilmstripStore(
            camera: CameraName("driveway"),
            previews: previews,
            imageLoader: FakePreviewImageLoader()
        ),
        scrubPreview: PreviewTileViewModel(
            camera: camera,
            previews: previews,
            recordings: recordings,
            imageLoader: FakePreviewImageLoader()
        ),
        liveSource: nil,
        now: { at(10_000) },
        startingAt: at(5_000),
        days: 2
    )
}

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
