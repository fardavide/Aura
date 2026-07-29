import Foundation
import Testing

import CamerasDomain
import CamerasEntities
import TestDoubles
import TimelineDomain
@testable import TimelinePresentation

struct PlaybackSpeedTests {

    @Test func `given a speed then its rate is the numeric multiplier`() {
        #expect(PlaybackSpeed.fourX.rate == 4)
    }

    @Test func `given the speeds then they read as multipliers in ascending order`() {
        #expect(PlaybackSpeed.allCases.map(\.title) == ["1×", "2×", "4×", "8×"])
    }

    @Test func `when stepping through the ladder then it climbs and wraps back to the slowest`() {
        #expect(PlaybackSpeed.allCases.map(\.next) == [.twoX, .fourX, .eightX, .oneX])
    }
}

@MainActor
struct RecordingPlayerViewModelTests {

    // MARK: - Loading

    @Test func `given footage when loading then it plays the window's stream`() async {
        // given
        let sut = makeViewModel(segments: fullHour(from: 3600))

        // when
        await sut.loadIfNeeded()

        // then
        #expect(isReady(sut.display))
        #expect(sut.isPlaying)
        #expect(sut.hasFootage)
    }

    @Test func `given a mid-hour instant when loading then the fetched window starts on the hour`() async {
        // given
        let repository = FakeCameraRecordingsRepository(.success(fullHour(from: 3600)))
        let sut = makeViewModel(repository: repository)

        // when
        await sut.loadIfNeeded()

        // then
        #expect(repository.lastWindow == TimeRange(start: at(3600), end: at(7200)))
    }

    @Test func `given an already loaded player when loading again then it does not refetch`() async {
        // given
        let repository = FakeCameraRecordingsRepository(.success(fullHour(from: 3600)))
        let sut = makeViewModel(repository: repository)
        await sut.loadIfNeeded()

        // when
        await sut.loadIfNeeded()

        // then
        #expect(repository.fetchCount == 1)
    }

    @Test func `given a window with no footage when loading then it reports none`() async {
        // given
        let sut = makeViewModel(segments: [])

        // when
        await sut.loadIfNeeded()

        // then
        #expect(isNoFootage(sut.display))
        #expect(!sut.isPlaying)
    }

    @Test func `given a failing repository when loading then it reports the failure`() async {
        // given
        let sut = makeViewModel(repository: FakeCameraRecordingsRepository(.failure(.serverUnavailable)))

        // when
        await sut.loadIfNeeded()

        // then
        #expect(isFailed(sut.display))
    }

    @Test func `given a playhead inside a gap when loading then it plays but reports no footage there`() async {
        // given — footage only in the first five minutes of the hour, playhead well past it
        let sut = makeViewModel(segments: [segment(from: 3600, to: 3900)])

        // when
        await sut.loadIfNeeded()

        // then
        #expect(isReady(sut.display))
        #expect(!sut.hasFootage)
    }

    // MARK: - Transport

    @Test func `given a playing recording when toggling play pause then it pauses`() async {
        // given
        let sut = makeViewModel(segments: fullHour(from: 3600))
        await sut.loadIfNeeded()

        // when
        sut.togglePlayPause()

        // then
        #expect(!sut.isPlaying)
    }

    @Test func `given a paused recording when toggling play pause then it resumes`() async {
        // given
        let sut = makeViewModel(segments: fullHour(from: 3600))
        await sut.loadIfNeeded()
        sut.togglePlayPause()

        // when
        sut.togglePlayPause()

        // then
        #expect(sut.isPlaying)
    }

    @Test func `when selecting a speed then it is applied`() async {
        // given
        let sut = makeViewModel(segments: fullHour(from: 3600))
        await sut.loadIfNeeded()

        // when
        sut.select(.fourX)

        // then
        #expect(sut.speed == .fourX)
        #expect(sut.isPlaying)
    }

    @Test func `given a paused recording when selecting a speed then it stays paused`() async {
        // given
        let sut = makeViewModel(segments: fullHour(from: 3600))
        await sut.loadIfNeeded()
        sut.togglePlayPause()

        // when
        sut.select(.eightX)

        // then
        #expect(sut.speed == .eightX)
        #expect(!sut.isPlaying)
    }

    // MARK: - Skipping

    @Test func `given a playhead mid-window when skipping forward then it advances by the interval`() async {
        // given
        let sut = makeViewModel(segments: fullHour(from: 3600), startingAt: at(5000))
        await sut.loadIfNeeded()

        // when
        await sut.skip(by: 10)

        // then
        #expect(sut.instant == at(5010))
    }

    @Test func `given a playhead mid-window when skipping backward then it rewinds by the interval`() async {
        // given
        let sut = makeViewModel(segments: fullHour(from: 3600), startingAt: at(5000))
        await sut.loadIfNeeded()

        // when
        await sut.skip(by: -10)

        // then
        #expect(sut.instant == at(4990))
    }

    @Test func `given a skip landing inside the window then no further window is fetched`() async {
        // given
        let repository = FakeCameraRecordingsRepository(.success(fullHour(from: 3600)))
        let sut = makeViewModel(repository: repository, startingAt: at(5000))
        await sut.loadIfNeeded()

        // when
        await sut.skip(by: 10)

        // then
        #expect(repository.fetchCount == 1)
    }

    // Ten seconds back means ten seconds of *footage* back — a gap has no length in the stream, so
    // a backward skip steps over it instead of sticking at the near edge.
    @Test func `given a gap behind the playhead when skipping backward then it crosses into the earlier footage`() async {
        // given — a minute of footage, a gap, then another minute; playhead ten seconds into the second
        let sut = makeViewModel(
            segments: [segment(from: 3600, to: 3660), segment(from: 4000, to: 4060)],
            startingAt: at(4010)
        )
        await sut.loadIfNeeded()

        // when
        await sut.skip(by: -20)

        // then — ten seconds back through the second segment, then ten more into the first
        #expect(sut.instant == at(3650))
    }

    @Test func `given a skip past the window end then the following window is fetched`() async {
        // given
        let repository = FakeCameraRecordingsRepository(.success(twoHours))
        let sut = makeViewModel(repository: repository, startingAt: at(7195))
        await sut.loadIfNeeded()

        // when
        await sut.skip(by: 10)

        // then
        #expect(repository.lastWindow == TimeRange(start: at(7200), end: at(10_800)))
        #expect(sut.instant == at(7200))
    }

    @Test func `given a skip before the window start then the preceding window is fetched`() async {
        // given — the hour before holds footage up to its final minute
        let repository = FakeCameraRecordingsRepository(.success([segment(from: 3300, to: 3600)]))
        let sut = makeViewModel(repository: repository, startingAt: at(3605))
        await sut.loadIfNeeded()

        // when
        await sut.skip(by: -10)

        // then — it opens the previous hour on its newest footage
        #expect(repository.lastWindow == TimeRange(start: at(0), end: at(3600)))
        #expect(sut.instant == at(3600))
    }

    @Test func `given a playhead at the newest footage when skipping forward then it stays put`() async {
        // given
        let sut = makeViewModel(segments: [segment(from: 7200, to: 7295)], startingAt: at(7295))
        await sut.loadIfNeeded()

        // when
        await sut.skip(by: 10)

        // then — nothing past it has been recorded yet
        #expect(sut.instant == at(7295))
    }

    @Test func `given a skip into another window then the speed and play state are carried over`() async {
        // given
        let sut = makeViewModel(segments: twoHours, startingAt: at(7195))
        await sut.loadIfNeeded()
        sut.select(.fourX)
        sut.togglePlayPause()

        // when
        await sut.skip(by: 10)

        // then
        #expect(isReady(sut.display))
        #expect(sut.speed == .fourX)
        #expect(!sut.isPlaying)
    }

    // The in-progress hour fills up as the clock runs. A window whose identity moved with it would
    // make every skip a refetch — a torn-down player and a fresh stream load for a cheap seek.
    @Test func `given time has passed when skipping inside the live hour then no further window is fetched`() async {
        // given
        let clock = Clock(at(9005))
        let repository = FakeCameraRecordingsRepository(.success(footage(from: 7200, to: 9005)))
        let sut = makeViewModel(repository: repository, startingAt: at(9000), clock: clock)
        await sut.loadIfNeeded()

        // when — three seconds of wall clock pass, then the playhead is nudged back
        clock.instant = at(9008)
        await sut.skip(by: -10)

        // then
        #expect(repository.fetchCount == 1)
        #expect(sut.instant == at(8990))
    }

    @Test func `given a pause taken during a window load then it is not reverted when the load lands`() async {
        // given — the second fetch is held open and the transport is paused inside it
        let repository = FakeCameraRecordingsRepository(.success(twoHours))
        let sut = makeViewModel(repository: repository, startingAt: at(7195))
        await sut.loadIfNeeded()
        repository.onSegments = { [weak sut] call in
            guard call == 2 else { return }
            await sut?.togglePlayPause()
        }

        // when
        await sut.skip(by: 10)

        // then
        #expect(!sut.isPlaying)
    }

    // Two window loads can be in flight at once — rapid skips, or a skip racing the end-of-window
    // advance. Whichever the server answers last must not be the one that wins.
    @Test func `given a window load overtaken by a newer one then the stale load is discarded`() async {
        // given — the second fetch is held open while a newer skip is issued and completes inside it
        let repository = FakeCameraRecordingsRepository(.success(twoHours))
        let sut = makeViewModel(repository: repository, startingAt: at(7195))
        await sut.loadIfNeeded()
        repository.onSegments = { [weak sut] call in
            guard call == 2 else { return }
            await sut?.skip(by: -10)
        }

        // when — this skip leaves the window, so it fetches, and is overtaken mid-flight
        await sut.skip(by: 10)

        // then — the newer seek stands, not the stale window that landed after it
        #expect(sut.instant == at(7185))
    }

    // MARK: - Running past the window

    @Test func `when the window plays out then the following window is fetched and plays on`() async {
        // given
        let repository = FakeCameraRecordingsRepository(.success(twoHours))
        let sut = makeViewModel(repository: repository, startingAt: at(5000))
        await sut.loadIfNeeded()

        // when
        await sut.advanceToNextWindow()

        // then
        #expect(repository.lastWindow == TimeRange(start: at(7200), end: at(10_800)))
        #expect(sut.isPlaying)
    }

    // MARK: - The day timeline

    @Test func `given a camera when loading then its own overlays are fetched over the span`() async {
        // given
        let overlays = FakeCameraDayTimelineRepository(.success(activity))
        let sut = makeViewModel(segments: fullHour(from: 3600), overlays: overlays)

        // when
        await sut.loadIfNeeded()

        // then — scoped to this camera, one day-sized window at a time, live edge first
        #expect(overlays.queriedScopes.allSatisfy { $0 == .camera(CameraName("driveway")) })
        #expect(overlays.queriedRanges == [
            TimeRange(start: at(-79_100), end: now),
            TimeRange(start: at(7300 - 2 * 86_400), end: at(-79_100)),
        ])
        #expect(sut.dayTimeline == activity)
    }

    @Test func `given the overlays fail when loading then the recording still plays`() async {
        // given
        let sut = makeViewModel(
            segments: fullHour(from: 3600),
            overlays: FakeCameraDayTimelineRepository(.failure(.serverUnavailable))
        )

        // when
        await sut.loadIfNeeded()

        // then — the timeline panel degrades to empty rather than failing the screen
        #expect(isReady(sut.display))
        #expect(sut.dayTimeline == DayTimeline(markers: [], motion: [], gaps: []))
    }

    @Test func `when refreshing then the span is extended to the present and the overlays re-read`() async {
        // given
        let clock = Clock(now)
        let overlays = FakeCameraDayTimelineRepository(.success(activity))
        let sut = makeViewModel(segments: fullHour(from: 3600), overlays: overlays, clock: clock)
        await sut.loadIfNeeded()

        // when
        clock.instant = at(10_000)
        await sut.refreshOverlays()

        // then — the start is fixed for the screen's life; only the stretch since the last read
        // is re-queried, one bucket back for the seam
        #expect(sut.span == TimeRange(start: at(7300 - 2 * 86_400), end: at(10_000)))
        #expect(overlays.queriedRanges.last == TimeRange(start: at(7154), end: at(10_000)))
        #expect(overlays.queriedRanges.count == 3)
    }

    @Test func `given a failing refresh then the last good overlays are kept`() async {
        // given
        let overlays = FakeCameraDayTimelineRepository(.success(activity))
        let sut = makeViewModel(segments: fullHour(from: 3600), overlays: overlays)
        await sut.loadIfNeeded()

        // when
        overlays.result = .failure(.unreachable)
        await sut.refreshOverlays()

        // then
        #expect(sut.dayTimeline == activity)
    }

    @Test func `given overlays cut short when refreshing at the live edge then the walk resumes`() async {
        // given — every overlay window failed on load, so the track is bare
        let clock = Clock(now)
        let overlays = FakeCameraDayTimelineRepository(.failure(.unreachable))
        let sut = makeViewModel(segments: fullHour(from: 3600), overlays: overlays, startingAt: at(7000), clock: clock)
        await sut.loadIfNeeded()
        #expect(sut.dayTimeline == DayTimeline(markers: [], motion: [], gaps: []))
        #expect(overlays.queriedRanges.count == 1)
        overlays.result = .success(activity)
        clock.instant = at(7350)

        // when
        await sut.refreshOverlays()

        // then — the live-edge delta lands, then the whole span is back-filled day by day
        #expect(sut.dayTimeline == activity)
        #expect(sut.span.end == at(7350))
        #expect(Array(overlays.queriedRanges.dropFirst()) == [
            TimeRange(start: at(7154), end: at(7350)),
            TimeRange(start: at(-79_246), end: at(7154)),
            TimeRange(start: at(-165_500), end: at(-79_246)),
        ])
    }

    // MARK: - The refresh gate

    @Test func `given the playhead near the live edge then a periodic refresh is due`() async {
        let sut = makeViewModel(segments: fullHour(from: 3600), startingAt: at(7000))
        await sut.loadIfNeeded()
        #expect(sut.shouldRefreshNow)
    }

    @Test func `given the playhead browsing history then a periodic refresh is suppressed`() async {
        let sut = makeViewModel(segments: fullHour(from: 3600), startingAt: at(5000))
        await sut.loadIfNeeded()
        #expect(!sut.shouldRefreshNow)
    }

    // MARK: - Zoom

    @Test func `given the default zoom when selecting another then it is applied`() async {
        // given
        let sut = makeViewModel(segments: fullHour(from: 3600))

        // when
        sut.select(TimelineZoom.week)

        // then
        #expect(sut.zoom == .week)
    }

    // MARK: - Seeking

    @Test func `given an instant inside the loaded window when seeking then it moves without refetching`() async {
        // given
        let repository = FakeCameraRecordingsRepository(.success(fullHour(from: 3600)))
        let sut = makeViewModel(repository: repository, startingAt: at(5000))
        await sut.loadIfNeeded()

        // when
        await sut.seek(to: at(6000))

        // then
        #expect(sut.instant == at(6000))
        #expect(repository.fetchCount == 1)
    }

    @Test func `given an instant in another hour when seeking then that window is loaded`() async {
        // given
        let repository = FakeCameraRecordingsRepository(.success(twoHours))
        let sut = makeViewModel(repository: repository, startingAt: at(5000))
        await sut.loadIfNeeded()

        // when
        await sut.seek(to: at(7250))

        // then
        #expect(repository.lastWindow == TimeRange(start: at(7200), end: at(10_800)))
        #expect(sut.instant == at(7250))
    }

    @Test func `given an instant outside the span when seeking then it is clamped to it`() async {
        // given
        let sut = makeViewModel(segments: fullHour(from: 3600))
        await sut.loadIfNeeded()

        // when
        await sut.seek(to: at(999_999))

        // then
        #expect(sut.instant == now)
    }

    // The readout must say where the playhead actually is, so the hero can report the gap — the
    // stream collapses gaps away, so reading the instant back off the player would hide it.
    @Test func `given a gap when seeking into it then the readout holds the instant and reports no footage`() async {
        // given — footage only in the first five minutes of the hour
        let sut = makeViewModel(segments: [segment(from: 3600, to: 3900)], startingAt: at(3700))
        await sut.loadIfNeeded()

        // when
        await sut.seek(to: at(5000))

        // then
        #expect(sut.instant == at(5000))
        #expect(!sut.hasFootage)
    }

    // MARK: - Scrubbing the track

    @Test func `given a drag when scrubbing then the readout follows without loading a window`() async {
        // given
        let repository = FakeCameraRecordingsRepository(.success(twoHours))
        let sut = makeViewModel(repository: repository, startingAt: at(5000))
        await sut.loadIfNeeded()

        // when — a drag that runs into the next hour
        sut.scrub(to: at(6000))
        sut.scrub(to: at(7250))

        // then — the fetch waits for the finger to lift
        #expect(sut.instant == at(7250))
        #expect(repository.fetchCount == 1)
    }

    @Test func `given a drag past the live edge when scrubbing then it is clamped to the span`() async {
        // given
        let sut = makeViewModel(segments: fullHour(from: 3600))
        await sut.loadIfNeeded()

        // when
        sut.scrub(to: at(999_999))

        // then
        #expect(sut.instant == now)
    }

    @Test func `when the drag ends then the window under the playhead is loaded`() async {
        // given
        let repository = FakeCameraRecordingsRepository(.success(twoHours))
        let sut = makeViewModel(repository: repository, startingAt: at(5000))
        await sut.loadIfNeeded()
        sut.scrub(to: at(7250))

        // when
        await sut.endScrub()

        // then
        #expect(repository.lastWindow == TimeRange(start: at(7200), end: at(10_800)))
        #expect(sut.instant == at(7250))
    }

    @Test func `given a playing recording when a drag starts then it pauses`() async {
        // given
        let sut = makeViewModel(segments: fullHour(from: 3600))
        await sut.loadIfNeeded()

        // when
        sut.beginScrub()

        // then — the drag and the transport would otherwise both drive the playhead
        #expect(!sut.isPlaying)
    }

    @Test func `given a playing recording when a drag settles then playback resumes`() async {
        // given
        let sut = makeViewModel(segments: fullHour(from: 3600))
        await sut.loadIfNeeded()
        sut.beginScrub()

        // when
        sut.scrub(to: at(6000))
        await sut.endScrub()

        // then — the pause was the drag's, not the user's; letting go hands playback back
        #expect(sut.isPlaying)
    }

    @Test func `given a paused recording when a drag settles then it stays paused`() async {
        // given
        let sut = makeViewModel(segments: fullHour(from: 3600))
        await sut.loadIfNeeded()
        sut.togglePlayPause()
        sut.beginScrub()

        // when
        sut.scrub(to: at(6000))
        await sut.endScrub()

        // then
        #expect(!sut.isPlaying)
    }

    @Test func `given a drag settling on an hour with no footage then playback is not resumed`() async {
        // given
        let repository = FakeCameraRecordingsRepository(.success(twoHours))
        let sut = makeViewModel(repository: repository, startingAt: at(5000))
        await sut.loadIfNeeded()
        sut.beginScrub()
        sut.scrub(to: at(7250))

        // when — the hour the drag settled on turns out to hold nothing playable
        repository.result = .success([])
        await sut.endScrub()

        // then
        #expect(!sut.isPlaying)
    }

    @Test func `given play toggled twice during a drag then settling leaves it paused`() async {
        // given — the user pressed play and then pause mid-drag; that explicit intent wins
        let sut = makeViewModel(segments: fullHour(from: 3600))
        await sut.loadIfNeeded()
        sut.beginScrub()
        sut.togglePlayPause()
        sut.togglePlayPause()

        // when
        await sut.endScrub()

        // then
        #expect(!sut.isPlaying)
    }

    // MARK: - Jumping

    @Test func `given markers when jumping forward then the playhead lands on the next marker's start`() async {
        // given
        let sut = makeViewModel(
            segments: fullHour(from: 3600),
            overlays: FakeCameraDayTimelineRepository(.success(activity)),
            startingAt: at(4000)
        )
        await sut.loadIfNeeded()

        // when
        await sut.jumpToNextMarker()

        // then
        #expect(sut.instant == at(5000))
    }

    @Test func `given markers when jumping back then the playhead lands on the previous marker's start`() async {
        // given
        let sut = makeViewModel(
            segments: fullHour(from: 3600),
            overlays: FakeCameraDayTimelineRepository(.success(activity)),
            startingAt: at(5500)
        )
        await sut.loadIfNeeded()

        // when
        await sut.jumpToPreviousMarker()

        // then
        #expect(sut.instant == at(5000))
    }

    @Test func `given no marker in that direction when jumping then the playhead stays put`() async {
        // given
        let sut = makeViewModel(
            segments: fullHour(from: 3600),
            overlays: FakeCameraDayTimelineRepository(.success(activity)),
            startingAt: at(3700)
        )
        await sut.loadIfNeeded()

        // when
        await sut.jumpToPreviousMarker()

        // then
        #expect(sut.instant == at(3700))
    }

    @Test func `given an instant inside a marker then it is the active one`() async {
        // given
        let sut = makeViewModel(
            segments: fullHour(from: 3600),
            overlays: FakeCameraDayTimelineRepository(.success(activity)),
            startingAt: at(5010)
        )

        // when
        await sut.loadIfNeeded()

        // then
        #expect(sut.state.activeMarker?.severity == .alert)
    }

    // MARK: - Day stepping and the live edge

    @Test func `when stepping back a day then the playhead moves a day earlier`() async {
        // given
        let sut = makeViewModel(segments: fullHour(from: 3600), startingAt: at(90_000))
        await sut.loadIfNeeded()

        // when
        await sut.stepDay(by: -1)

        // then
        #expect(sut.instant == at(90_000 - 86_400))
    }

    @Test func `given the live edge when stepping forward a day then the playhead clamps to it`() async {
        // given
        let sut = makeViewModel(segments: fullHour(from: 3600), startingAt: at(5000))
        await sut.loadIfNeeded()

        // when
        await sut.stepDay(by: 1)

        // then
        #expect(sut.instant == now)
    }

    @Test func `given a playhead in the past when going live then it jumps to the newest footage`() async {
        // given
        let sut = makeViewModel(segments: twoHours, startingAt: at(5000))
        await sut.loadIfNeeded()
        #expect(!sut.state.isLive)

        // when
        await sut.goLive()

        // then
        #expect(sut.instant == now)
        #expect(sut.state.isLive)
    }

    // Driven by a *moving* clock: the in-progress hour grows while it plays, and the live-edge
    // check has to read "no later hour exists yet" rather than "the window looks different now" —
    // otherwise the end of the stream reloads the same hour and rewinds to the top of it.
    @Test func `given the live hour when the stream plays out then playback stops where it is`() async {
        // given
        let clock = Clock(at(9005))
        let repository = FakeCameraRecordingsRepository(.success(footage(from: 7200, to: 9005)))
        let sut = makeViewModel(repository: repository, startingAt: at(9000), clock: clock)
        await sut.loadIfNeeded()

        // when — the stream runs out a few seconds later, and the server has nothing newer yet
        clock.instant = at(9012)
        await sut.advanceToNextWindow()

        // then — one catch-up refetch of the growing hour, no rewind to the top of it, and the
        // playhead now reads as parked on the live edge
        #expect(!sut.isPlaying)
        #expect(sut.instant == at(9000))
        #expect(repository.fetchCount == 2)
        #expect(sut.state.isLive)
    }

    @Test func `given new footage when the live hour plays out then playback continues into it`() async {
        // given
        let clock = Clock(at(9005))
        let repository = FakeCameraRecordingsRepository(.success(footage(from: 7200, to: 9005)))
        let sut = makeViewModel(repository: repository, startingAt: at(9000), clock: clock)
        await sut.loadIfNeeded()

        // when — by the time the stream runs out, the server has recorded on
        clock.instant = at(9040)
        repository.result = .success(footage(from: 7200, to: 9040))
        await sut.advanceToNextWindow()

        // then — the grown hour is refetched and playback carries on at the live edge
        #expect(sut.isPlaying)
        #expect(sut.state.isLive)
        #expect(repository.fetchCount == 2)
    }

    // MARK: - Following the live edge

    @Test func `given footage short of the present when going live then it parks on the newest footage`() async {
        // given — the live hour's footage stops well short of the wall clock
        let repository = FakeCameraRecordingsRepository(.success(footage(from: 7200, to: 7250)))
        let sut = makeViewModel(repository: repository, startingAt: at(5000))
        await sut.loadIfNeeded()

        // when
        await sut.goLive()

        // then — parked a hair inside the newest clip, so the readout matches the shown frame
        #expect(sut.instant == at(7249.5))
        #expect(sut.hasFootage)
        #expect(sut.state.isLive)
    }

    @Test func `given a recording opened at the live edge then it reads live from the start`() async {
        // given - when
        let sut = makeViewModel(segments: footage(from: 7200, to: 7300), startingAt: now)
        await sut.loadIfNeeded()

        // then
        #expect(sut.state.isLive)
    }

    @Test func `given a live playhead when a forward skip finds nothing newer then it stays live`() async {
        // given
        let sut = makeViewModel(segments: footage(from: 7200, to: 7295), startingAt: at(5000))
        await sut.loadIfNeeded()
        await sut.goLive()

        // when — nothing past the newest footage exists yet, so the skip is a no-op
        await sut.skip(by: 10)

        // then — a move that didn't happen must not demote the playhead to history
        #expect(sut.state.isLive)
    }

    @Test func `given a live playhead when skipping back then it reads as history`() async {
        // given
        let sut = makeViewModel(segments: footage(from: 3600, to: 7300), startingAt: at(5000))
        await sut.loadIfNeeded()
        await sut.goLive()

        // when
        await sut.skip(by: -10)

        // then
        #expect(!sut.state.isLive)
    }

    @Test func `given a drag ending at the span end then it reads live`() async {
        // given
        let sut = makeViewModel(segments: footage(from: 3600, to: 7300), startingAt: at(5000))
        await sut.loadIfNeeded()
        sut.beginScrub()

        // when
        sut.scrub(to: at(999_999))
        await sut.endScrub()

        // then
        #expect(sut.state.isLive)
    }
}

// MARK: - Helpers

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private let now = at(7300)

private let camera = Camera(name: CameraName("driveway"), friendlyName: "Driveway", isEnabled: true, streamNames: ["driveway"])

/// A clock a test can wind forward. Playback of the in-progress hour behaves differently as the
/// present moves, and a frozen clock hides that entirely — so anything touching the live edge
/// drives one of these instead of the fixed `now`.
@MainActor
private final class Clock {
    var instant: Date

    init(_ instant: Date) {
        self.instant = instant
    }
}

private func segment(from start: TimeInterval, to end: TimeInterval) -> RecordingSegment {
    RecordingSegment(range: TimeRange(start: at(start), end: at(end)), duration: end - start)
}

/// Unbroken footage in five-minute segments — short enough that the server would serve every one
/// of them (it drops anything reaching ten minutes), so the whole span is playable.
private func footage(from start: TimeInterval, to end: TimeInterval) -> [RecordingSegment] {
    stride(from: start, to: end, by: 300).map { segment(from: $0, to: min($0 + 300, end)) }
}

private func fullHour(from start: TimeInterval) -> [RecordingSegment] {
    footage(from: start, to: start + 3600)
}

/// Unbroken footage spanning both the window under test and the one after it, so a swap has
/// something to play on the other side.
private let twoHours = fullHour(from: 3600) + fullHour(from: 7200)

/// Two markers on the loaded hour — one alert, one detection — plus a little motion, so the jump
/// buttons and the active-marker badge have something to find.
private let activity = DayTimeline(
    markers: [
        ReviewMarker(start: at(3800), end: at(3860), severity: .detection),
        ReviewMarker(start: at(5000), end: at(5060), severity: .alert),
    ],
    motion: [MotionBucket(time: at(3800), intensity: 40)],
    gaps: []
)

@MainActor
private func makeViewModel(
    repository: FakeCameraRecordingsRepository,
    overlays: FakeCameraDayTimelineRepository = FakeCameraDayTimelineRepository(
        .success(DayTimeline(markers: [], motion: [], gaps: []))
    ),
    startingAt instant: Date = at(5000),
    clock: Clock? = nil
) -> RecordingPlayerViewModel {
    RecordingPlayerViewModel(
        camera: camera,
        recordings: GetCameraRecordings(repository: repository),
        getDayTimeline: GetDayTimeline(repository: overlays),
        now: { clock?.instant ?? now },
        startingAt: instant,
        days: 2
    )
}

@MainActor
private func makeViewModel(
    segments: [RecordingSegment],
    overlays: FakeCameraDayTimelineRepository = FakeCameraDayTimelineRepository(
        .success(DayTimeline(markers: [], motion: [], gaps: []))
    ),
    startingAt instant: Date = at(5000),
    clock: Clock? = nil
) -> RecordingPlayerViewModel {
    makeViewModel(
        repository: FakeCameraRecordingsRepository(.success(segments)),
        overlays: overlays,
        startingAt: instant,
        clock: clock
    )
}

private func isReady(_ display: RecordingPlayerViewModel.Display) -> Bool {
    if case .ready = display { return true }
    return false
}

private func isNoFootage(_ display: RecordingPlayerViewModel.Display) -> Bool {
    if case .noFootage = display { return true }
    return false
}

private func isFailed(_ display: RecordingPlayerViewModel.Display) -> Bool {
    if case .failed = display { return true }
    return false
}
