import Foundation
import Testing

import CamerasDomain
import CamerasEntities
import SettingsDomain
import TestDoubles
import TimelineDomain
@testable import TimelinePresentation

@MainActor
struct ScrubClockTests {

    @Test func `given a scrub then the instant updates`() {
        let clock = ScrubClock(instant: at(0))
        clock.scrub(to: at(50))
        #expect(clock.instant == at(50))
    }

    @Test func `given begin then end scrub then the flag toggles`() {
        let clock = ScrubClock(instant: at(0))
        clock.beginScrub()
        #expect(clock.isScrubbing)
        clock.endScrub()
        #expect(!clock.isScrubbing)
    }
}

@MainActor
struct PreviewTileControllerTests {

    @Test func `given an idle controller when scrubbing then it seeks immediately`() {
        let scrubber = FakePreviewScrubber()
        let sut = PreviewTileController(scrubber: scrubber, tolerance: 0.5)
        sut.scrub(to: at(10))
        #expect(scrubber.targets == [at(10)])
    }

    @Test func `given scrubs while seeking when it completes then only the latest is applied`() {
        let scrubber = FakePreviewScrubber()
        let sut = PreviewTileController(scrubber: scrubber, tolerance: 0.5)
        sut.scrub(to: at(10))   // seeks 10
        sut.scrub(to: at(20))   // coalesced
        sut.scrub(to: at(30))   // latest pending
        scrubber.complete()     // applies 30 (the in-between 20 is dropped)
        #expect(scrubber.targets == [at(10), at(30)])
    }

    @Test func `given a pending target within tolerance when it completes then it is not re-applied`() {
        let scrubber = FakePreviewScrubber()
        let sut = PreviewTileController(scrubber: scrubber, tolerance: 0.5)
        sut.scrub(to: at(10))
        sut.scrub(to: at(10.2))   // within 0.5s of the applied target
        scrubber.complete()
        #expect(scrubber.targets == [at(10)])
    }

    @Test func `given no pending when it completes then a later scrub seeks again`() {
        let scrubber = FakePreviewScrubber()
        let sut = PreviewTileController(scrubber: scrubber, tolerance: 0.5)
        sut.scrub(to: at(10))
        scrubber.complete()
        sut.scrub(to: at(20))
        #expect(scrubber.targets == [at(10), at(20)])
    }
}

@MainActor
struct TimelineScreenViewModelTests {

    @Test func `given cameras and a timeline when loading then it is ready`() async {
        let sut = makeViewModel(cameras: .success([camera]), timeline: .success(emptyTimeline))
        await sut.load()
        #expect(sut.state == .ready(cameras: [camera], timeline: emptyTimeline))
    }

    @Test func `given no cameras when loading then it is empty`() async {
        let sut = makeViewModel(cameras: .success([]), timeline: .success(emptyTimeline))
        await sut.load()
        #expect(sut.state == .empty)
    }

    @Test func `given a camera failure when loading then it fails mapped to a timeline error`() async {
        let sut = makeViewModel(cameras: .failure(.notAuthorized), timeline: .success(emptyTimeline))
        await sut.load()
        #expect(sut.state == .failed(.notAuthorized))
    }

    @Test func `given a timeline failure when loading then it fails`() async {
        let sut = makeViewModel(cameras: .success([camera]), timeline: .failure(.serverUnavailable))
        await sut.load()
        #expect(sut.state == .failed(.serverUnavailable))
    }

    @Test func `given a scrub before the span starts then it is clamped into the span`() {
        let sut = makeViewModel(cameras: .success([camera]), timeline: .success(emptyTimeline))
        sut.scrub(to: sut.span.start.addingTimeInterval(-100))
        #expect(sut.clock.instant == sut.span.start)
    }

    @Test func `given a ready timeline when refreshing then it re-queries with the span extended to now`() async {
        // given
        let clock = TestClock(at(1_000_000))
        let timelineRepo = FakeCameraDayTimelineRepository(.success(emptyTimeline))
        let sut = TimelineScreenViewModel(
            observeCameras: makeObserveCameras(repository: FakeCamerasRepository(.success([camera]))),
            getDayTimeline: GetDayTimeline(repository: timelineRepo),
            now: { clock.value },
            days: 2
        )
        await sut.load()
        clock.value = at(1_000_030)

        // when
        await sut.refresh()

        // then
        #expect(sut.span.end == at(1_000_030))
        #expect(timelineRepo.queriedRanges.last == TimeRange(start: sut.span.start, end: at(1_000_030)))
        #expect(sut.span.start == at(1_000_000 - 2 * 86_400))
    }

    @Test func `given a refresh failure when refreshing then the last good timeline is kept`() async {
        // given
        let timelineRepo = FakeCameraDayTimelineRepository(.success(busyTimeline))
        let sut = TimelineScreenViewModel(
            observeCameras: makeObserveCameras(repository: FakeCamerasRepository(.success([camera]))),
            getDayTimeline: GetDayTimeline(repository: timelineRepo),
            now: { at(1_000_000) },
            days: 2
        )
        await sut.load()
        timelineRepo.result = .failure(.serverUnavailable)

        // when
        await sut.refresh()

        // then
        #expect(sut.state == .ready(cameras: [camera], timeline: busyTimeline))
    }

    @Test func `given a failed load when refreshing recovers then it becomes ready`() async {
        // given
        let timelineRepo = FakeCameraDayTimelineRepository(.failure(.unreachable))
        let sut = TimelineScreenViewModel(
            observeCameras: makeObserveCameras(repository: FakeCamerasRepository(.success([camera]))),
            getDayTimeline: GetDayTimeline(repository: timelineRepo),
            now: { at(1_000_000) },
            days: 2
        )
        await sut.load()
        #expect(sut.state == .failed(.unreachable))
        timelineRepo.result = .success(busyTimeline)

        // when
        await sut.refresh()

        // then
        #expect(sut.state == .ready(cameras: [camera], timeline: busyTimeline))
    }

    @Test func `given a ready timeline at the live edge and not scrubbing then a refresh is due`() async {
        let sut = makeViewModel(cameras: .success([camera]), timeline: .success(emptyTimeline))
        await sut.load()
        #expect(sut.shouldRefreshNow)
    }

    @Test func `given a scrub back into history then a refresh is suppressed`() async {
        let sut = makeViewModel(cameras: .success([camera]), timeline: .success(emptyTimeline))
        await sut.load()
        sut.scrub(to: sut.span.start)
        #expect(!sut.shouldRefreshNow)
    }

    @Test func `given an active scrub then a refresh is suppressed`() async {
        let sut = makeViewModel(cameras: .success([camera]), timeline: .success(emptyTimeline))
        await sut.load()
        sut.clock.beginScrub()
        #expect(!sut.shouldRefreshNow)
    }

    @Test func `given a failed state then a refresh is due so it can recover`() async {
        let sut = makeViewModel(cameras: .success([camera]), timeline: .failure(.unreachable))
        await sut.load()
        #expect(sut.shouldRefreshNow)
    }

    @Test func `given a loaded state when loadIfNeeded then it does not fetch again`() async {
        // given
        let cameras = FakeCamerasRepository(.success([camera]))
        let sut = TimelineScreenViewModel(
            observeCameras: makeObserveCameras(repository: cameras),
            getDayTimeline: GetDayTimeline(repository: FakeCameraDayTimelineRepository(.success(emptyTimeline))),
            now: { at(1_000_000) },
            days: 2
        )
        await sut.load()

        // when
        await sut.loadIfNeeded()

        // then
        #expect(cameras.fetchCount == 1)
        #expect(sut.state == .ready(cameras: [camera], timeline: emptyTimeline))
    }

    @Test func `given an order change landing during a refresh fetch then the fresh order wins`() async {
        // given
        let settings = FakeSettingsRepository()
        let timelineRepo = FakeCameraDayTimelineRepository(.success(emptyTimeline))
        let sut = TimelineScreenViewModel(
            observeCameras: makeObserveCameras(
                repository: FakeCamerasRepository(.success([camera, garageCamera])),
                settings: settings
            ),
            getDayTimeline: GetDayTimeline(repository: timelineRepo),
            now: { at(1_000_000) },
            days: 2
        )
        await sut.load()

        // when — the reorder lands while the refresh's timeline fetch is in flight
        timelineRepo.onQuery = {
            await MainActor.run { settings.saveCameraOrder([CameraName("garage"), CameraName("driveway")]) }
            for _ in 0..<20 { await Task.yield() }
        }
        await sut.refresh()

        // then
        #expect(sut.state == .ready(cameras: [garageCamera, camera], timeline: emptyTimeline))
    }

    @Test func `given a ready timeline when the order changes then the cameras re-sort`() async {
        // given
        let settings = FakeSettingsRepository()
        let sut = makeViewModel(
            cameras: .success([camera, garageCamera]),
            timeline: .success(emptyTimeline),
            settings: settings
        )
        await sut.load()

        // when
        settings.saveCameraOrder([CameraName("garage"), CameraName("driveway")])

        // then
        let resorted: TimelineScreenViewModel.State = .ready(cameras: [garageCamera, camera], timeline: emptyTimeline)
        for _ in 0..<100 where sut.state != resorted {
            await Task.yield()
        }
        #expect(sut.state == resorted)
    }
}

// MARK: - Helpers

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private let camera = Camera(name: CameraName("driveway"), friendlyName: "Driveway", isEnabled: true, streamNames: ["driveway"])
private let garageCamera = Camera(name: CameraName("garage"), friendlyName: "Garage", isEnabled: true, streamNames: ["garage"])
private let emptyTimeline = DayTimeline(markers: [], motion: [], gaps: [])
private let busyTimeline = DayTimeline(markers: [], motion: [MotionBucket(time: at(1_000), intensity: 80)], gaps: [])

@MainActor
private func makeViewModel(
    cameras: Result<[Camera], CamerasError>,
    timeline: Result<DayTimeline, TimelineError>,
    settings: FakeSettingsRepository = FakeSettingsRepository()
) -> TimelineScreenViewModel {
    TimelineScreenViewModel(
        observeCameras: makeObserveCameras(repository: FakeCamerasRepository(cameras), settings: settings),
        getDayTimeline: GetDayTimeline(repository: FakeCameraDayTimelineRepository(timeline)),
        now: { at(1_000_000) },
        days: 2
    )
}

@MainActor
private func makeObserveCameras(
    repository: any CamerasRepository,
    settings: FakeSettingsRepository = FakeSettingsRepository()
) -> ObserveCameras {
    ObserveCameras(
        getCameras: GetCameras(repository: repository),
        observeCameraOrder: ObserveCameraOrder(repository: settings)
    )
}

/// A mutable clock so a test can advance "now" between a load and a refresh.
@MainActor
private final class TestClock {
    var value: Date
    init(_ value: Date) { self.value = value }
}

@MainActor
private final class FakePreviewScrubber: PreviewScrubber {
    private(set) var targets: [Date] = []
    private var completion: (@MainActor () -> Void)?

    func scrub(to time: Date, completion: @escaping @MainActor () -> Void) {
        targets.append(time)
        self.completion = completion
    }

    func complete() {
        let pending = completion
        completion = nil
        pending?()
    }
}
