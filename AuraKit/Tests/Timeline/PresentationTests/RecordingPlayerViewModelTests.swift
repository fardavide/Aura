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

    // Driven by a *moving* clock: the in-progress hour grows while it plays, and the live-edge
    // check has to read "no later hour exists yet" rather than "the window looks different now" —
    // otherwise the end of the stream reloads the same hour and rewinds to the top of it.
    @Test func `given the live hour when the stream plays out then playback stops where it is`() async {
        // given
        let clock = Clock(at(9005))
        let repository = FakeCameraRecordingsRepository(.success(footage(from: 7200, to: 9005)))
        let sut = makeViewModel(repository: repository, startingAt: at(9000), clock: clock)
        await sut.loadIfNeeded()

        // when — the stream runs out a few seconds later
        clock.instant = at(9012)
        await sut.advanceToNextWindow()

        // then — no rewind to the top of the hour, and no second fetch of the same window
        #expect(!sut.isPlaying)
        #expect(sut.instant == at(9000))
        #expect(repository.fetchCount == 1)
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

@MainActor
private func makeViewModel(
    repository: FakeCameraRecordingsRepository,
    startingAt instant: Date = at(5000),
    clock: Clock? = nil
) -> RecordingPlayerViewModel {
    RecordingPlayerViewModel(
        camera: camera,
        recordings: GetCameraRecordings(repository: repository),
        now: { clock?.instant ?? now },
        startingAt: instant
    )
}

@MainActor
private func makeViewModel(
    segments: [RecordingSegment],
    startingAt instant: Date = at(5000)
) -> RecordingPlayerViewModel {
    makeViewModel(repository: FakeCameraRecordingsRepository(.success(segments)), startingAt: instant)
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
