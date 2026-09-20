import Foundation
import SwiftUI
import Testing

import CamerasDomain
import CamerasEntities
import ExportsDomain
import ExportsPresentation
import TestDoubles

/// Screenshot tests for the Exports tab across the states the design names, captured on every
/// device + orientation (iOS). Thumbnails resolve to `nil`, pinning every card to the deterministic
/// no-thumbnail placeholder; times are fixed instants rendered through the pinned snapshot
/// environment (POSIX locale, GMT).
@MainActor
struct ExportsListSnapshotTests {

    @Test func `given exports when loaded then it matches the reference`() async {
        // given
        let view = await exportsScreen(exports: .success(snapshotExports()))

        // then
        assertScreenSnapshot(view, named: "loaded")
    }

    @Test func `given no exports when empty then it matches the reference`() async {
        // given
        let view = await exportsScreen(exports: .success([]))

        // then
        assertScreenSnapshot(view, named: "empty")
    }

    @Test func `given an unreachable server when failed then it matches the reference`() async {
        // given
        let view = await exportsScreen(exports: .failure(.unreachable))

        // then
        assertScreenSnapshot(view, named: "unreachable")
    }

    @Test func `given a clip still being cut then the processing card matches the reference`() async {
        // given
        let view = await exportsScreen(exports: .success(snapshotProcessingExports()))

        // then
        assertScreenSnapshot(view, named: "processing")
    }

    @Test func `given a transfer in flight then the downloading card matches the reference`() async {
        // given
        let view = await exportsScreen(
            exports: .success(snapshotExports()),
            transfer: .inFlight(ExportTransfer(bytesReceived: 3_400_000, bytesExpected: 5_500_000))
        )

        // then
        assertScreenSnapshot(view, named: "downloading")
    }

    @Test func `given a failed transfer then the error strip matches the reference`() async {
        // given
        let view = await exportsScreen(exports: .success(snapshotExports()), transfer: .failed)

        // then
        assertScreenSnapshot(view, named: "download-failed")
    }

    @Test func `given a refresh that failed over content then the stale banner matches the reference`() async {
        // given
        let view = await exportsScreen(exports: .success(snapshotExports()), refreshFails: true)

        // then
        assertScreenSnapshot(view, named: "stale")
    }

    @Test func `given no camera names when loaded then cards fall back to the slug`() async {
        // given
        let view = await exportsScreen(exports: .success(snapshotExports()), cameras: .failure(.unreachable))

        // then
        assertScreenSnapshot(view, named: "no-cameras")
    }
}

// MARK: - Fixtures

/// A few days of clips across the snapshot cameras: distinct instants so the newest-first order and
/// the day grouping are both stable, one clip with an empty name to exercise truncation's other
/// end, and a spread across Today / Yesterday / an older day.
private func snapshotExports() -> [Export] {
    func at(hoursAgo: Double) -> Date { snapshotNow.addingTimeInterval(-hoursAgo * 3600) }

    return [
        export("exp-1", camera: "driveway", at: at(hoursAgo: 2)),
        export("exp-2", camera: "front_door", at: at(hoursAgo: 6)),
        export("exp-3", camera: "backyard", at: at(hoursAgo: 27)),
        export("exp-4", camera: "garage", at: at(hoursAgo: 52)),
    ]
}

/// The same library with the newest clip still being cut — the disabled controls, the reason text
/// and the hatched frame all in one card, beside ready ones for contrast.
private func snapshotProcessingExports() -> [Export] {
    var exports = snapshotExports()
    exports[0] = export("exp-1", camera: "driveway", at: exports[0].createdAt, isProcessing: true)
    return exports
}

private func export(
    _ id: String,
    camera: String,
    at createdAt: Date,
    isProcessing: Bool = false
) -> Export {
    Export(
        id: ExportId(id),
        camera: CameraName(camera),
        name: "\(camera)_20260918_143012",
        createdAt: createdAt,
        isProcessing: isProcessing,
        videoPath: "/media/frigate/exports/\(id).mp4",
        thumbnailPath: nil
    )
}

// MARK: - View builder

private enum SnapshotTransfer {
    case none
    case inFlight(ExportTransfer)
    case failed
}

/// The Exports screen, driven to a terminal state before rendering so the view's own `.task`
/// re-load settles on the same pixels.
@MainActor
private func exportsScreen(
    exports: Result<[Export], ExportsError>,
    cameras: Result<[Camera], CamerasError> = .success(snapshotCameras()),
    transfer: SnapshotTransfer = .none,
    refreshFails: Bool = false
) async -> some View {
    let repository = FakeExportsRepository(exports)
    let viewModel = ExportsListViewModel(
        getExports: GetExports(repository: repository),
        getCameras: GetCameras(repository: FakeCamerasRepository(cameras)),
        thumbnailLoader: FakeExportThumbnailLoader(),
        serverLabel: "frigate.local:5000",
        now: { snapshotNow },
        calendar: {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            return calendar
        }(),
        // Long enough that the poll never fires mid-capture.
        processingPollInterval: .seconds(3_600),
        minimumRetryDuration: .zero,
        // Long enough that the screen's own re-entry refresh never earns the pill mid-capture —
        // the references show the resting header, not a transient one.
        refreshIndicatorDelay: .seconds(3_600)
    )
    await viewModel.load()
    if refreshFails {
        repository.result = .failure(.unreachable)
        await viewModel.refresh()
    }

    let downloads = await downloadCenter(transfer: transfer, for: exports)
    return ExportsListView(
        viewModel: viewModel,
        downloads: downloads,
        onOpenSettings: {},
        onOpenTimeline: {},
        // Unused: the player factory is never invoked in a list snapshot (no navigation happens).
        makePlayerViewModel: {
            ExportPlayerViewModel(export: $0, playback: FakeExportPlaybackProvider())
        }
    )
}

@MainActor
private func downloadCenter(
    transfer: SnapshotTransfer,
    for exports: Result<[Export], ExportsError>
) async -> DownloadCenter {
    let downloader: FakeExportDownloader
    switch transfer {
    case .none:
        downloader = FakeExportDownloader()
    case .inFlight(let progress):
        downloader = FakeExportDownloader(steps: [progress], staysInFlight: true)
    case .failed:
        downloader = FakeExportDownloader(.failure(.unreachable))
    }
    let center = DownloadCenter(
        downloadExport: DownloadExport(downloader: downloader),
        cancelledNoticeDuration: .seconds(3_600)
    )
    switch transfer {
    case .none:
        return center
    case .inFlight, .failed:
        guard let first = try? exports.get().first else { return center }
        center.download(first)
        // The centre drives its work from a task; wait for the state the capture depends on rather
        // than sleeping a fixed amount and hoping.
        for _ in 0..<200 where center.state(for: first.id) == nil
            || center.state(for: first.id) == .transferring(ExportTransfer(bytesReceived: 0, bytesExpected: nil)) {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return center
    }
}
