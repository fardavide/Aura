import AVFoundation
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

    @Test func `given failing overlay endpoints when loading then the grid still paints`() async {
        let sut = makeViewModel(cameras: .success([camera]), timeline: .failure(.serverUnavailable))
        await sut.load()
        #expect(sut.state == .ready(cameras: [camera], timeline: emptyTimeline))
    }

    @Test func `when loading then the span is read newest-first one day at a time`() async {
        // given
        let timelineRepo = FakeCameraDayTimelineRepository(.success(emptyTimeline))
        let sut = TimelineScreenViewModel(
            observeCameras: makeObserveCameras(repository: FakeCamerasRepository(.success([camera]))),
            getDayTimeline: GetDayTimeline(repository: timelineRepo),
            now: { at(1_000_000) },
            days: 2
        )

        // when
        await sut.load()

        // then — two day-sized windows, live edge first, at the span's bucket resolution
        #expect(timelineRepo.queriedRanges == [
            TimeRange(start: at(913_600), end: at(1_000_000)),
            TimeRange(start: at(827_200), end: at(913_600)),
        ])
        #expect(timelineRepo.queriedBuckets.allSatisfy { $0 == 86 })
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

        // then — only the stretch since the last read is re-queried, one bucket back for the seam
        #expect(sut.span.end == at(1_000_030))
        #expect(timelineRepo.queriedRanges.last == TimeRange(start: at(999_884), end: at(1_000_030)))
        #expect(sut.span.start == at(1_000_000 - 2 * 86_400))
    }

    @Test func `given overlays cut short by an unreachable server when refreshing then the walk resumes`() async {
        // given — the server answers the newest day's window, then goes down mid-walk
        let clock = TestClock(at(1_000_000))
        let timelineRepo = FakeCameraDayTimelineRepository(.success(emptyTimeline))
        timelineRepo.onQuery = { [weak timelineRepo] in
            guard let timelineRepo, timelineRepo.queriedRanges.count == 2 else { return }
            timelineRepo.result = .failure(.unreachable)
        }
        let sut = TimelineScreenViewModel(
            observeCameras: makeObserveCameras(repository: FakeCamerasRepository(.success([camera]))),
            getDayTimeline: GetDayTimeline(repository: timelineRepo),
            now: { clock.value },
            days: 2
        )
        await sut.load()
        #expect(timelineRepo.queriedRanges.count == 2)
        timelineRepo.onQuery = nil
        timelineRepo.result = .success(emptyTimeline)
        clock.value = at(1_000_030)

        // when
        await sut.refresh()

        // then — the live-edge delta lands first, then the missing day is fetched
        #expect(Array(timelineRepo.queriedRanges.dropFirst(2)) == [
            TimeRange(start: at(999_884), end: at(1_000_030)),
            TimeRange(start: at(827_200), end: at(913_600)),
        ])
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
        // given — the camera read failed, so the whole screen failed
        let cameras = FakeCamerasRepository(.failure(.unreachable))
        let sut = TimelineScreenViewModel(
            observeCameras: makeObserveCameras(repository: cameras),
            getDayTimeline: GetDayTimeline(repository: FakeCameraDayTimelineRepository(.success(busyTimeline))),
            now: { at(1_000_000) },
            days: 2
        )
        await sut.load()
        #expect(sut.state == .failed(.unreachable))
        cameras.result = .success([camera])

        // when
        await sut.refresh()

        // then — cameras and the whole overlay span are re-read
        #expect(sut.state == .ready(cameras: [camera], timeline: busyTimeline))
    }

    @Test func `given a stale ready screen when auto-refresh starts then it refreshes immediately`() async {
        // given — loaded at t0; "now" has since moved on (e.g. the screen was re-entered later)
        let clock = TestClock(at(1_000_000))
        let sut = TimelineScreenViewModel(
            observeCameras: makeObserveCameras(repository: FakeCamerasRepository(.success([camera]))),
            getDayTimeline: GetDayTimeline(repository: FakeCameraDayTimelineRepository(.success(emptyTimeline))),
            now: { clock.value },
            days: 2
        )
        await sut.load()
        clock.value = at(1_000_300)

        // when — the loop starts with an interval far longer than the test
        let loop = Task { await sut.autoRefresh(every: .seconds(600)) }
        await settle { sut.span.end == at(1_000_300) }
        loop.cancel()

        // then — the live edge caught up without waiting a tick
        #expect(sut.span.end == at(1_000_300))
    }

    @Test func `given the playhead parked at the live edge when a refresh extends the span then the playhead follows`() async {
        // given — a suspension far longer than the live-edge gate window (the reported bug: reopen
        // the app hours later), so the follow must be judged against the *old* span end
        let clock = TestClock(at(1_000_000))
        let sut = TimelineScreenViewModel(
            observeCameras: makeObserveCameras(repository: FakeCamerasRepository(.success([camera]))),
            getDayTimeline: GetDayTimeline(repository: FakeCameraDayTimelineRepository(.success(emptyTimeline))),
            now: { clock.value },
            days: 2
        )
        await sut.load()
        clock.value = at(1_000_000 + 7_200)

        // when
        await sut.refresh()

        // then — the readout and the tiles track the present, not the pre-refresh live edge
        #expect(sut.clock.instant == at(1_000_000 + 7_200))
    }

    @Test func `given the playhead parked minutes behind the live edge when a refresh lands then the playhead stays put`() async {
        // given — parked 3 minutes back (inside the refresh-gate window, but deliberately not live)
        let clock = TestClock(at(1_000_000))
        let sut = TimelineScreenViewModel(
            observeCameras: makeObserveCameras(repository: FakeCamerasRepository(.success([camera]))),
            getDayTimeline: GetDayTimeline(repository: FakeCameraDayTimelineRepository(.success(emptyTimeline))),
            now: { clock.value },
            days: 2
        )
        await sut.load()
        sut.scrub(to: at(1_000_000 - 180))
        clock.value = at(1_000_030)

        // when
        await sut.refresh()

        // then — re-watching something minutes old is never interrupted by a tick
        #expect(sut.clock.instant == at(1_000_000 - 180))
    }

    @Test func `given a scrub begun and settled during the refresh fetch then the playhead stays put`() async {
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

        // when — a whole drag into history begins AND ends while the fetch is in flight
        timelineRepo.onQuery = {
            await MainActor.run {
                sut.clock.beginScrub()
                sut.scrub(to: at(1_000_000 - 10_800))
                sut.clock.endScrub()
            }
        }
        await sut.refresh()

        // then — the settled position survives the landing
        #expect(sut.clock.instant == at(1_000_000 - 10_800))
    }

    @Test func `given a refresh already in flight when refreshing again then the fetches coalesce`() async {
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
        timelineRepo.onQuery = { for _ in 0..<20 { await Task.yield() } }

        // when — the scene-activation catch-up and the loop's immediate check race
        async let first: Void = sut.refresh()
        async let second: Void = sut.refresh()
        _ = await (first, second)

        // then — two windows for the load, one shared delta for both refresh calls
        #expect(timelineRepo.queriedRanges.count == 3)
    }

    @Test func `given the playhead scrubbed into history when a refresh extends the span then the playhead stays put`() async {
        // given — parked two hours back, well outside the live-edge window
        let clock = TestClock(at(1_000_000))
        let sut = TimelineScreenViewModel(
            observeCameras: makeObserveCameras(repository: FakeCamerasRepository(.success([camera]))),
            getDayTimeline: GetDayTimeline(repository: FakeCameraDayTimelineRepository(.success(emptyTimeline))),
            now: { clock.value },
            days: 2
        )
        await sut.load()
        sut.scrub(to: at(1_000_000 - 7_200))
        clock.value = at(1_000_030)

        // when
        await sut.refresh()

        // then
        #expect(sut.clock.instant == at(1_000_000 - 7_200))
    }

    @Test func `given an active scrub when a refresh lands then the playhead stays put`() async {
        // given — the user is mid-drag at the live edge
        let clock = TestClock(at(1_000_000))
        let sut = TimelineScreenViewModel(
            observeCameras: makeObserveCameras(repository: FakeCamerasRepository(.success([camera]))),
            getDayTimeline: GetDayTimeline(repository: FakeCameraDayTimelineRepository(.success(emptyTimeline))),
            now: { clock.value },
            days: 2
        )
        await sut.load()
        sut.clock.beginScrub()
        clock.value = at(1_000_030)

        // when
        await sut.refresh()

        // then — the drag is never yanked to the new live edge
        #expect(sut.clock.instant == at(1_000_000))
    }

    @Test func `given a scrub starting while the refresh is in flight then the playhead stays put`() async {
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

        // when — the drag begins while the refresh's timeline fetch is in flight
        timelineRepo.onQuery = { await MainActor.run { sut.clock.beginScrub() } }
        await sut.refresh()

        // then
        #expect(sut.clock.instant == at(1_000_000))
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

@MainActor
struct PreviewTileViewModelTests {

    @Test func `given the live hour with frames then it shows the nearest frame, not a frozen clip`() async {
        // given — a past-hour clip [0,60] and current-hour frames at 70 and 80
        let loader = FakePreviewImageLoader(image: pngData)
        let sut = makeTile(clips: [clip(0, 60)], frames: [frame(70), frame(80)], loader: loader)

        // when — the playhead sits in the live hour, past the last clip
        await sut.prepare(range: tileWindow, at: at(85))
        await settle { isFrame(sut.display) }

        // then — the nearest frame at or before 85 is loaded and shown
        #expect(loader.requestedFrames.last == frame(80))
        #expect(isFrame(sut.display))
    }

    @Test func `given a scrub covered by a past clip then it plays the clip without loading a frame`() async {
        let loader = FakePreviewImageLoader(image: pngData)
        let sut = makeTile(clips: [clip(0, 60)], frames: [frame(70)], loader: loader)

        await sut.prepare(range: tileWindow, at: at(30))

        #expect(isClip(sut.display))
        #expect(loader.requestedFrames.isEmpty)
    }

    @Test func `given the live edge with no frames then it freezes on the latest clip`() async {
        let loader = FakePreviewImageLoader(image: pngData)
        let sut = makeTile(clips: [clip(0, 60)], frames: [], loader: loader)

        await sut.prepare(range: tileWindow, at: at(90))

        #expect(isClip(sut.display))
        #expect(loader.requestedFrames.isEmpty)
    }

    @Test func `given no clips and only frames then it shows a frame`() async {
        let loader = FakePreviewImageLoader(image: pngData)
        let sut = makeTile(clips: [], frames: [frame(70), frame(80), frame(90)], loader: loader)

        await sut.prepare(range: tileWindow, at: at(85))
        await settle { isFrame(sut.display) }

        #expect(loader.requestedFrames.last == frame(80))
    }

    @Test func `given the span grew when preparing again then the tile shows the newly recorded frame`() async {
        // given — prepared at the live edge of the original window, frames up to 80
        let provider = FakeCameraPreviewProvider(clips: [clip(0, 60)], frames: [frame(70), frame(80)])
        let loader = FakePreviewImageLoader(image: pngData)
        let sut = makeTile(provider: provider, loader: loader)
        await sut.prepare(range: tileWindow, at: at(85))
        await settle { isFrame(sut.display) }

        // when — the timeline refresh grew the span and newer footage exists now
        provider.framesResult = .success([frame(70), frame(80), frame(140), frame(150)])
        await sut.prepare(range: TimeRange(start: at(0), end: at(160)), at: at(155))
        await settle { loader.requestedFrames.last == frame(150) }

        // then — the freshest frame is shown, not the stale pre-refresh one
        #expect(loader.requestedFrames.last == frame(150))
        #expect(isFrame(sut.display))
    }

    @Test func `given an active clip when preparing again for a grown span then the player is not rebuilt`() async throws {
        // given — the tile plays a past-hour clip
        let provider = FakeCameraPreviewProvider(clips: [clip(0, 60)])
        let sut = makeTile(provider: provider, loader: FakePreviewImageLoader(image: pngData))
        await sut.prepare(range: tileWindow, at: at(30))
        let playerBefore = try #require(player(of: sut.display))

        // when — the timeline refresh grew the span and the view re-prepares, then a scrub
        // resolves a value-equal clip (driven through the scrubber seam directly, so the check
        // cannot go vacuous on the coalescer's in-flight state)
        await sut.prepare(range: TimeRange(start: at(0), end: at(160)), at: at(30))
        sut.scrub(to: at(35)) { }

        // then — the same player keeps playing: refreshed in place, no teardown flash
        #expect(player(of: sut.display) === playerBefore)
    }

    @Test func `given loaded material when a refresh fetch fails then the last good material is kept`() async {
        // given
        let provider = FakeCameraPreviewProvider(clips: [clip(0, 60)], frames: [frame(70), frame(80)])
        let loader = FakePreviewImageLoader(image: pngData)
        let sut = makeTile(provider: provider, loader: loader)
        await sut.prepare(range: tileWindow, at: at(85))
        await settle { isFrame(sut.display) }

        // when — the periodic re-prepare hits a transient failure
        provider.clipsResult = .failure(.unreachable)
        await sut.prepare(range: TimeRange(start: at(0), end: at(160)), at: at(85))

        // then — still the last good frame, not a full-tile error
        #expect(isFrame(sut.display))
    }

    @Test func `given a frames fetch failure during the refresh then the last good frames are kept`() async {
        // given — a loaded tile showing the live-hour frame
        let provider = FakeCameraPreviewProvider(clips: [clip(0, 60)], frames: [frame(70), frame(80)])
        let loader = FakePreviewImageLoader(image: pngData)
        let sut = makeTile(provider: provider, loader: loader)
        await sut.prepare(range: tileWindow, at: at(85))
        await settle { isFrame(sut.display) }

        // when — the periodic re-prepare gets clips but the frames fetch blips
        provider.framesResult = .failure(.unreachable)
        await sut.prepare(range: TimeRange(start: at(0), end: at(160)), at: at(85))

        // then — the previously loaded frame still shows; nothing was reloaded or degraded
        #expect(isFrame(sut.display))
        #expect(loader.requestedFrames == [frame(80)])
    }

    @Test func `given a scrub during the material refresh then the latest instant wins, not the captured one`() async {
        // given — a loaded tile showing the live-hour frame
        let provider = FakeCameraPreviewProvider(clips: [clip(0, 60)], frames: [frame(70), frame(80)])
        let loader = FakePreviewImageLoader(image: pngData)
        let sut = makeTile(provider: provider, loader: loader)
        await sut.prepare(range: tileWindow, at: at(85))
        await settle { isFrame(sut.display) }

        // when — the user scrubs into a past clip while the refresh's refetch is in flight
        provider.onClips = { await MainActor.run { sut.scrub(to: at(30)) } }
        await sut.prepare(range: TimeRange(start: at(0), end: at(160)), at: at(85))
        await settle { isFrame(sut.display) }

        // then — the tile stays on the user's instant, not the refresh's stale capture
        #expect(isClip(sut.display))
    }

    @Test func `given the first load cancelled mid-flight then the tile does not show an error`() async {
        // given — a first load held in flight; a torn-down fetch surfaces as unreachable
        let provider = FakeCameraPreviewProvider(clips: [clip(0, 60)])
        provider.onClips = { while !Task.isCancelled { await Task.yield() } }
        provider.clipsResult = .failure(.unreachable)
        let sut = makeTile(provider: provider, loader: FakePreviewImageLoader(image: pngData))

        // when — the owning task is cancelled (the view re-keys, or the tile leaves the screen)
        let load = Task { await sut.prepare(range: tileWindow, at: at(30)) }
        await Task.yield()
        load.cancel()
        await load.value

        // then — still the loading placeholder, not a spurious error tile
        #expect(isLoading(sut.display))
    }

    @Test func `given a failed tile when preparing again then it recovers`() async {
        // given — the initial load failed outright
        let provider = FakeCameraPreviewProvider()
        provider.clipsResult = .failure(.unreachable)
        let loader = FakePreviewImageLoader(image: pngData)
        let sut = makeTile(provider: provider, loader: loader)
        await sut.prepare(range: tileWindow, at: at(85))

        // when — the next span refresh retries and the server is back
        provider.clipsResult = .success([clip(0, 60)])
        provider.framesResult = .success([frame(70), frame(80)])
        await sut.prepare(range: tileWindow, at: at(85))
        await settle { isFrame(sut.display) }

        // then
        #expect(isFrame(sut.display))
    }

    // MARK: Following the live edge (a trigger separate from the first load)

    @Test func `given a tile still on its first load when following the live edge then it is left untouched`() async {
        // given — a fresh tile whose first load has not run yet (still on the spinner)
        let provider = FakeCameraPreviewProvider(clips: [clip(0, 60)], frames: [frame(70), frame(80)])
        let sut = makeTile(provider: provider, loader: FakePreviewImageLoader(image: pngData))

        // when — the live-edge follow fires (as it does on appear) while nothing is loaded yet
        await sut.followLiveEdge(to: tileWindow, at: at(85))

        // then — it neither fetched nor resolved the display: the first load still owns the material
        #expect(isLoading(sut.display))
        #expect(provider.clipsCallCount == 0)
    }

    @Test func `given the first load in flight when the live edge grows then the load finishes instead of stranding`() async {
        // given — a first load held mid-fetch (a slow server), so the tile sits on its spinner
        let gate = Gate()
        let provider = FakeCameraPreviewProvider(clips: [clip(0, 60)], frames: [frame(70), frame(80)])
        provider.onClips = { await gate.wait() }
        let sut = makeTile(provider: provider, loader: FakePreviewImageLoader(image: pngData))
        let firstLoad = Task { await sut.prepare(range: tileWindow, at: at(85)) }
        await settle { provider.clipsCallCount == 1 }

        // when — the 30s live-edge refresh grows the span while the first load is still in flight
        await sut.followLiveEdge(to: TimeRange(start: at(0), end: at(160)), at: at(155))

        // then — the follow left the in-flight load alone: it neither restarted nor duplicated it
        #expect(isLoading(sut.display))
        #expect(provider.clipsCallCount == 1)

        // and when the load finally lands it resolves the tile, rather than spinning forever
        await gate.open()
        await firstLoad.value
        await settle { isFrame(sut.display) }
        #expect(isFrame(sut.display))
    }

    @Test func `given a loaded tile when the live edge grows then following it refreshes the material in place`() async {
        // given — a loaded tile showing the live-hour frame
        let provider = FakeCameraPreviewProvider(clips: [clip(0, 60)], frames: [frame(70), frame(80)])
        let loader = FakePreviewImageLoader(image: pngData)
        let sut = makeTile(provider: provider, loader: loader)
        await sut.prepare(range: tileWindow, at: at(85))
        await settle { isFrame(sut.display) }

        // when — newer footage exists and the live edge grows past it
        provider.framesResult = .success([frame(70), frame(80), frame(140), frame(150)])
        await sut.followLiveEdge(to: TimeRange(start: at(0), end: at(160)), at: at(155))
        await settle { loader.requestedFrames.last == frame(150) }

        // then — the freshest frame is shown, not the stale pre-refresh one
        #expect(loader.requestedFrames.last == frame(150))
        #expect(isFrame(sut.display))
    }

    @Test func `given a failed tile when the live edge grows then following it retries from scratch`() async {
        // given — the first load failed outright
        let provider = FakeCameraPreviewProvider()
        provider.clipsResult = .failure(.unreachable)
        let loader = FakePreviewImageLoader(image: pngData)
        let sut = makeTile(provider: provider, loader: loader)
        await sut.prepare(range: tileWindow, at: at(85))
        #expect(isFailed(sut.display))

        // when — the server recovers and the next extension follows the live edge
        provider.clipsResult = .success([clip(0, 60)])
        provider.framesResult = .success([frame(70), frame(80)])
        await sut.followLiveEdge(to: tileWindow, at: at(85))
        await settle { isFrame(sut.display) }

        // then — the tile self-recovers with the screen
        #expect(isFrame(sut.display))
    }

    @Test func `given the first load's frame image fails then the tile resolves to a placeholder, not a stuck spinner`() async {
        // given — live-hour frames exist, but the frame image can't be decoded (nil)
        let provider = FakeCameraPreviewProvider(clips: [clip(0, 60)], frames: [frame(70), frame(80)])
        let sut = makeTile(provider: provider, loader: FakePreviewImageLoader(image: nil))

        // when — the first load runs at the live edge, past the last clip
        await sut.prepare(range: tileWindow, at: at(85))
        await settle { !isLoading(sut.display) }

        // then — it leaves the spinner for a definite placeholder, so followLiveEdge (which skips
        // `.loading`) can retry it, rather than reading it as a still-in-flight load forever
        #expect(isUnavailable(sut.display))
    }

    @Test func `given a placeholder from a failed first-load frame image when following the live edge then it retries`() async {
        // given — a first load whose frame image failed, so the tile shows the placeholder
        let provider = FakeCameraPreviewProvider(clips: [clip(0, 60)], frames: [frame(70), frame(80)])
        let loader = FakePreviewImageLoader(image: nil)
        let sut = makeTile(provider: provider, loader: loader)
        await sut.prepare(range: tileWindow, at: at(85))
        await settle { isUnavailable(sut.display) }

        // when — the image endpoint recovers and the next extension follows the live edge
        loader.image = pngData
        await sut.followLiveEdge(to: tileWindow, at: at(85))
        await settle { isFrame(sut.display) }

        // then — the tile self-recovers instead of spinning behind the live edge
        #expect(isFrame(sut.display))
    }
}

// MARK: - Helpers

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private let camera = Camera(name: CameraName("driveway"), friendlyName: "Driveway", isEnabled: true, streamNames: ["driveway"])
private let garageCamera = Camera(name: CameraName("garage"), friendlyName: "Garage", isEnabled: true, streamNames: ["garage"])
private let tileWindow = TimeRange(start: at(0), end: at(100))

/// A 1×1 PNG so `platformImage(from:)` decodes to a real image (arbitrary bytes decode to nil).
private let pngData = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
)!

private func clip(_ start: TimeInterval, _ end: TimeInterval) -> PreviewClip {
    PreviewClip(camera: camera.name, range: TimeRange(start: at(start), end: at(end)), path: "/p.mp4")
}

private func frame(_ seconds: TimeInterval) -> PreviewFrame {
    PreviewFrame(camera: camera.name, time: at(seconds), fileName: "preview_driveway-\(Int(seconds)).webp")
}

@MainActor
private func makeTile(
    clips: [PreviewClip],
    frames: [PreviewFrame],
    loader: FakePreviewImageLoader
) -> PreviewTileViewModel {
    makeTile(provider: FakeCameraPreviewProvider(clips: clips, frames: frames), loader: loader)
}

@MainActor
private func makeTile(provider: FakeCameraPreviewProvider, loader: FakePreviewImageLoader) -> PreviewTileViewModel {
    PreviewTileViewModel(
        camera: camera,
        previews: GetCameraPreviews(provider: provider),
        recordings: GetCameraRecordings(repository: FakeCameraRecordingsRepository(.success([]))),
        imageLoader: loader
    )
}

private func isFrame(_ display: PreviewTileViewModel.Display) -> Bool {
    if case .frame = display { true } else { false }
}

private func isClip(_ display: PreviewTileViewModel.Display) -> Bool {
    if case .clip = display { true } else { false }
}

private func isLoading(_ display: PreviewTileViewModel.Display) -> Bool {
    if case .loading = display { true } else { false }
}

private func isFailed(_ display: PreviewTileViewModel.Display) -> Bool {
    if case .failed = display { true } else { false }
}

private func isUnavailable(_ display: PreviewTileViewModel.Display) -> Bool {
    if case .unavailable = display { true } else { false }
}

private func player(of display: PreviewTileViewModel.Display) -> AVPlayer? {
    if case let .clip(player) = display { player } else { nil }
}

/// Spins the main actor until `condition` holds (the frame load hops through a `Task`), bounded so
/// a stuck expectation fails fast rather than hanging.
@MainActor
private func settle(_ condition: () -> Bool) async {
    for _ in 0..<100 where !condition() {
        await Task.yield()
    }
}
private let emptyTimeline = DayTimeline(markers: [], motion: [], gaps: [])
/// Motion inside the tests' two-day span (`now` 1,000,000 − 2 days) — content outside the span
/// would be clipped away by the window merge and the fixture would silently read as empty.
private let busyTimeline = DayTimeline(markers: [], motion: [MotionBucket(time: at(999_000), intensity: 80)], gaps: [])

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

/// A one-shot async gate: `wait()` suspends until `open()` is called (returning at once if already
/// open). Lets a test hold a fake fetch in flight, then release it to run to completion.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
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
