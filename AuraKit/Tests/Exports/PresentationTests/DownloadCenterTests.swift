import Foundation
import Testing

import CamerasEntities
import ExportsDomain
import TestDoubles
@testable import ExportsPresentation

@MainActor
struct DownloadCenterTests {

    @Test func `given no transfer then the export has no download state`() {
        #expect(makeSut().center.state(for: ExportId("a")) == nil)
    }

    @Test func `when a download finishes then the file is held for the platform to save`() async {
        // given
        let (center, downloader) = makeSut()

        // when
        center.download(export)
        await settle(center, until: { $0.state(for: export.id) == .readyToSave(downloaded) })

        // then
        #expect(center.state(for: export.id) == .readyToSave(downloaded))
        #expect(downloader.downloaded == [export.id])
    }

    @Test func `given a failing transfer when downloading then the card shows the failure`() async {
        // given
        let (center, _) = makeSut(result: .failure(.unreachable))

        // when
        center.download(export)
        await settle(center, until: { $0.state(for: export.id) == .failed(.unreachable) })

        // then
        #expect(center.state(for: export.id) == .failed(.unreachable))
    }

    @Test func `given a failure when it is dismissed then the card can offer download again`() async {
        // given — the failure is otherwise sticky and survives a scroll
        let (center, _) = makeSut(result: .failure(.unreachable))
        center.download(export)
        await settle(center, until: { $0.state(for: export.id) == .failed(.unreachable) })

        // when
        center.dismissFailure(export.id)

        // then
        #expect(center.state(for: export.id) == nil)
    }

    @Test func `when the platform is finished with the file then the temporary copy is deleted`() async {
        // given — Aura keeps no second library
        let (center, downloader) = makeSut()
        center.download(export)
        await settle(center, until: { $0.state(for: export.id) == .readyToSave(downloaded) })

        // when
        center.finishSaving(export.id)

        // then
        #expect(downloader.discarded == [downloaded])
        #expect(center.state(for: export.id) == nil)
    }

    @Test func `given a dismissed share sheet then it is not reported as a failure`() async {
        // given — dismissing without choosing a destination is not a failure
        let (center, _) = makeSut()
        center.download(export)
        await settle(center, until: { $0.state(for: export.id) == .readyToSave(downloaded) })

        // when
        center.finishSaving(export.id)

        // then
        #expect(center.state(for: export.id) == nil)
    }

    @Test func `when a transfer is cancelled then the card says so and then goes quiet`() async {
        // given
        let (center, _) = makeSut(noticeDuration: .milliseconds(30))
        center.download(export)

        // when
        center.cancel(export.id)

        // then
        #expect(center.state(for: export.id) == .cancelled)
        await settle(center, until: { $0.state(for: export.id) == nil })
        #expect(center.state(for: export.id) == nil)
    }

    @Test func `given a transfer already running when download is pressed again then no rival transfer starts`() async {
        // given
        let (center, downloader) = makeSut()
        center.download(export)

        // when
        center.download(export)
        await settle(center, until: { $0.state(for: export.id) == .readyToSave(downloaded) })

        // then
        #expect(downloader.downloaded == [export.id])
    }

    @Test func `given nothing in flight then the header has nothing to report`() {
        // given
        let (center, _) = makeSut()

        // then
        #expect(center.transferringCount == 0)
        #expect(center.overallFraction == nil)
    }

    @Test func `given a transfer in flight then the header counts it`() {
        // given
        let (center, _) = makeSut()

        // when
        center.download(export)

        // then
        #expect(center.transferringCount == 1)
    }
}

private let downloaded = DownloadedExport(fileUrl: URL(filePath: "/tmp/clip.mp4"), fileName: "clip.mp4")

private let export = Export(
    id: ExportId("a"),
    camera: CameraName("driveway"),
    name: "driveway_20260918_143012",
    createdAt: Date(timeIntervalSince1970: 100),
    isProcessing: false,
    videoPath: "/media/frigate/exports/a.mp4",
    thumbnailPath: nil
)

@MainActor
private func makeSut(
    result: Result<DownloadedExport, ExportsError> = .success(downloaded),
    noticeDuration: Duration = .milliseconds(10)
) -> (center: DownloadCenter, downloader: FakeExportDownloader) {
    let downloader = FakeExportDownloader(result)
    let center = DownloadCenter(
        downloadExport: DownloadExport(downloader: downloader),
        cancelledNoticeDuration: noticeDuration
    )
    return (center, downloader)
}

/// The centre drives its work from detached tasks, so a test waits for the state it expects rather
/// than sleeping a fixed amount and hoping.
@MainActor
private func settle(
    _ center: DownloadCenter,
    until condition: (DownloadCenter) -> Bool,
    limit: Int = 200
) async {
    for _ in 0..<limit where !condition(center) {
        try? await Task.sleep(for: .milliseconds(5))
    }
}
