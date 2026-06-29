import Foundation
import Testing

import CamerasDomain
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
        let scrubber = FakeScrubber()
        let sut = PreviewTileController(scrubber: scrubber, tolerance: 0.5)
        sut.scrub(to: at(10))
        #expect(scrubber.targets == [at(10)])
    }

    @Test func `given scrubs while seeking when it completes then only the latest is applied`() {
        let scrubber = FakeScrubber()
        let sut = PreviewTileController(scrubber: scrubber, tolerance: 0.5)
        sut.scrub(to: at(10))   // seeks 10
        sut.scrub(to: at(20))   // coalesced
        sut.scrub(to: at(30))   // latest pending
        scrubber.complete()     // applies 30 (the in-between 20 is dropped)
        #expect(scrubber.targets == [at(10), at(30)])
    }

    @Test func `given a pending target within tolerance when it completes then it is not re-applied`() {
        let scrubber = FakeScrubber()
        let sut = PreviewTileController(scrubber: scrubber, tolerance: 0.5)
        sut.scrub(to: at(10))
        sut.scrub(to: at(10.2))   // within 0.5s of the applied target
        scrubber.complete()
        #expect(scrubber.targets == [at(10)])
    }

    @Test func `given no pending when it completes then a later scrub seeks again`() {
        let scrubber = FakeScrubber()
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

    @Test func `given a loaded state when loadIfNeeded then it does not fetch again`() async {
        // given
        let cameras = CountingCamerasRepository(.success([camera]))
        let sut = TimelineScreenViewModel(
            getCameras: GetCameras(repository: cameras),
            getDayTimeline: GetDayTimeline(repository: FakeTimelineRepository(.success(emptyTimeline))),
            now: at(1_000_000),
            days: 2
        )
        await sut.load()

        // when
        await sut.loadIfNeeded()

        // then
        #expect(cameras.fetchCount == 1)
        #expect(sut.state == .ready(cameras: [camera], timeline: emptyTimeline))
    }
}

// MARK: - Helpers

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private let camera = Camera(name: CameraName("driveway"), friendlyName: "Driveway", isEnabled: true, streamNames: ["driveway"])
private let emptyTimeline = DayTimeline(markers: [], motion: [], gaps: [])

@MainActor
private func makeViewModel(
    cameras: Result<[Camera], CamerasError>,
    timeline: Result<DayTimeline, TimelineError>
) -> TimelineScreenViewModel {
    TimelineScreenViewModel(
        getCameras: GetCameras(repository: FakeCamerasRepository(cameras)),
        getDayTimeline: GetDayTimeline(repository: FakeTimelineRepository(timeline)),
        now: at(1_000_000),
        days: 2
    )
}

private struct FakeCamerasRepository: CamerasRepository {
    let result: Result<[Camera], CamerasError>
    init(_ result: Result<[Camera], CamerasError>) { self.result = result }
    func cameras() async throws(CamerasError) -> [Camera] { try result.get() }
}

private struct FakeTimelineRepository: CameraDayTimelineRepository {
    let result: Result<DayTimeline, TimelineError>
    init(_ result: Result<DayTimeline, TimelineError>) { self.result = result }
    func dayTimeline(in range: TimeRange) async throws(TimelineError) -> DayTimeline { try result.get() }
}

@MainActor
private final class CountingCamerasRepository: CamerasRepository {
    private let result: Result<[Camera], CamerasError>
    private(set) var fetchCount = 0
    init(_ result: Result<[Camera], CamerasError>) { self.result = result }
    func cameras() async throws(CamerasError) -> [Camera] {
        fetchCount += 1
        return try result.get()
    }
}

@MainActor
private final class FakeScrubber: PreviewScrubber {
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
