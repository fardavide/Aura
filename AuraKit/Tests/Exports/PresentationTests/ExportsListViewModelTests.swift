import Foundation
import Testing

import CamerasDomain
import CamerasEntities
import ExportsDomain
import TestDoubles
@testable import ExportsPresentation

@MainActor
struct ExportsListViewModelTests {

    @Test func `given exports when loading then they are grouped by day, newest first`() async {
        // given
        let sut = makeSut(exports: [
            export("mon", at: day(1, hour: 9)),
            export("tue", at: day(2, hour: 9)),
        ])

        // when
        await sut.load()

        // then
        #expect(sut.groups.map { $0.exports.map(\.id) } == [[ExportId("tue")], [ExportId("mon")]])
    }

    @Test func `given no exports when loading then the list is empty`() async {
        // given
        let sut = makeSut(exports: [])

        // when
        await sut.load()

        // then
        #expect(sut.state == .empty)
    }

    @Test func `given an unreachable server on the first load then the list fails`() async {
        // given
        let sut = makeSut(result: .failure(.unreachable))

        // when
        await sut.load()

        // then
        #expect(sut.state == .failed(.unreachable))
        #expect(sut.hasStaleContent == false)
    }

    @Test func `given a loaded list when a refresh fails then the rows survive and the banner appears`() async {
        // given — the screen must never blank
        let repository = FakeExportsRepository(.success([export("a", at: 100)]))
        let sut = makeSut(repository: repository)
        await sut.load()

        // when
        repository.result = .failure(.unreachable)
        await sut.refresh()

        // then
        #expect(sut.state.hasContent)
        #expect(sut.groups.first?.exports.map(\.id) == [ExportId("a")])
        #expect(sut.hasStaleContent)
    }

    @Test func `given stale content when a refresh succeeds then the banner clears`() async {
        // given
        let repository = FakeExportsRepository(.success([export("a", at: 100)]))
        let sut = makeSut(repository: repository)
        await sut.load()
        repository.result = .failure(.unreachable)
        await sut.refresh()

        // when
        repository.result = .success([export("a", at: 100), export("b", at: 200)])
        await sut.refresh()

        // then
        #expect(sut.hasStaleContent == false)
        #expect(sut.groups.flatMap { $0.exports.map(\.id) } == [ExportId("b"), ExportId("a")])
    }

    @Test func `given a loaded list when loading again then it refreshes instead of returning to loading`() async {
        // given
        let repository = FakeExportsRepository(.success([export("a", at: 100)]))
        let sut = makeSut(repository: repository)
        await sut.load()

        // when — the screen's `.task` re-runs on every appearance
        repository.result = .failure(.unreachable)
        await sut.load()

        // then
        #expect(sut.state.hasContent)
    }

    @Test func `when the list has loaded then the header counts clips and distinct cameras`() async {
        // given
        let sut = makeSut(exports: [
            export("a", at: 100, camera: "driveway"),
            export("b", at: 200, camera: "driveway"),
            export("c", at: 300, camera: "garage"),
        ])

        // when
        await sut.load()

        // then
        #expect(sut.summary == ExportsSummary(clipCount: 3, cameraCount: 2))
    }

    @Test func `given the first load has not finished then there is no header count`() {
        #expect(makeSut(exports: []).summary == nil)
    }

    @Test func `given an empty library then the header counts zero rather than nothing`() async {
        // given
        let sut = makeSut(exports: [])

        // when
        await sut.load()

        // then
        #expect(sut.summary == ExportsSummary(clipCount: 0, cameraCount: 0))
    }

    @Test func `given a clip still being cut then the list knows it must keep polling`() async {
        // given
        let sut = makeSut(exports: [export("a", at: 100, isProcessing: true)])

        // when
        await sut.load()

        // then
        #expect(sut.hasProcessingExports)
    }

    @Test func `given every clip is finished then the list stops polling`() async {
        // given
        let sut = makeSut(exports: [export("a", at: 100)])

        // when
        await sut.load()

        // then
        #expect(sut.hasProcessingExports == false)
    }

    @Test func `given a known camera when naming it then the friendly name is used`() async {
        // given
        let sut = makeSut(
            exports: [export("a", at: 100, camera: "driveway")],
            cameras: .success([
                Camera(name: CameraName("driveway"), friendlyName: "Driveway", isEnabled: true, streamNames: []),
            ])
        )

        // when
        await sut.load()

        // then
        #expect(sut.displayName(for: CameraName("driveway")) == "Driveway")
    }

    @Test func `given the camera read failed when naming a camera then the slug is used`() async {
        // given — a failed camera read must not cost the list its content
        let sut = makeSut(exports: [export("a", at: 100, camera: "driveway")], cameras: .failure(.unreachable))

        // when
        await sut.load()

        // then
        #expect(sut.displayName(for: CameraName("driveway")) == "driveway")
        #expect(sut.state.hasContent)
    }

    @Test func `given a refresh that finishes quickly then the updating pill never appears`() async {
        // given — a pill that flashes on every tab visit is noise
        let sut = makeSut(exports: [export("a", at: 100)], refreshIndicatorDelay: .seconds(3_600))
        await sut.load()

        // when
        await sut.refresh()

        // then
        #expect(sut.isRefreshing == false)
    }

    @Test func `given a refresh that outlasts the delay then the updating pill appears`() async {
        // given — a read slow enough to outlast the delay, so there is an in-flight window to sample
        let repository = FakeExportsRepository(.success([export("a", at: 100)]))
        let sut = makeSut(repository: repository, refreshIndicatorDelay: .milliseconds(10))
        await sut.load()
        repository.delay = .milliseconds(300)
        var sawPill = false

        // when
        async let refresh: Void = sut.refresh()
        for _ in 0..<100 where !sawPill {
            try? await Task.sleep(for: .milliseconds(5))
            sawPill = sut.isRefreshing
        }
        await refresh

        // then
        #expect(sawPill)
        #expect(sut.isRefreshing == false)
    }

    @Test func `given a server that refuses instantly when retrying then the control stays busy long enough to read`() async {
        // given
        let sut = makeSut(result: .failure(.unreachable), minimumRetryDuration: .milliseconds(120))
        let started = ContinuousClock.now

        // when
        await sut.retry()

        // then
        #expect(ContinuousClock.now - started >= .milliseconds(120))
        #expect(sut.isRetrying == false)
    }
}

@MainActor
private func makeSut(
    repository: FakeExportsRepository,
    cameras: Result<[Camera], CamerasError> = .success([]),
    minimumRetryDuration: Duration = .zero,
    refreshIndicatorDelay: Duration = .seconds(3_600)
) -> ExportsListViewModel {
    ExportsListViewModel(
        getExports: GetExports(repository: repository),
        getCameras: GetCameras(repository: FakeCamerasRepository(cameras)),
        thumbnailLoader: FakeExportThumbnailLoader(),
        serverLabel: "frigate.local:5000",
        now: { Date(timeIntervalSince1970: 1_000) },
        calendar: gmtCalendar,
        processingPollInterval: .milliseconds(1),
        minimumRetryDuration: minimumRetryDuration,
        refreshIndicatorDelay: refreshIndicatorDelay
    )
}

@MainActor
private func makeSut(
    exports: [Export] = [],
    result: Result<[Export], ExportsError>? = nil,
    cameras: Result<[Camera], CamerasError> = .success([]),
    minimumRetryDuration: Duration = .zero,
    refreshIndicatorDelay: Duration = .seconds(3_600)
) -> ExportsListViewModel {
    makeSut(
        repository: FakeExportsRepository(result ?? .success(exports)),
        cameras: cameras,
        minimumRetryDuration: minimumRetryDuration,
        refreshIndicatorDelay: refreshIndicatorDelay
    )
}

private func export(
    _ id: String,
    at epoch: TimeInterval,
    camera: String = "driveway",
    isProcessing: Bool = false
) -> Export {
    Export(
        id: ExportId(id),
        camera: CameraName(camera),
        name: "\(camera)_20260918_143012",
        createdAt: Date(timeIntervalSince1970: epoch),
        isProcessing: isProcessing,
        videoPath: "/media/frigate/exports/\(id).mp4",
        thumbnailPath: nil
    )
}

private func day(_ day: Int, hour: Int) -> TimeInterval {
    gmtCalendar.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
        .timeIntervalSince1970
}

private let gmtCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}()
