import AVFoundation
import Foundation
import Testing

import CamerasDomain
import CamerasEntities
import TestDoubles
import TimelineDomain
@testable import TimelinePresentation

/// The tile's full-resolution mode: while the transport is running, a tile plays the recorded
/// stream instead of the low-res scrub material it seeks when parked.
@MainActor
struct PreviewTilePlaybackTests {

    // MARK: - Entering playback

    @Test func `given footage when playback begins then the tile plays the recorded stream`() async {
        // given
        let scenario = Scenario(segments: fullHour(from: 3600))

        // when
        await scenario.sut.beginPlayback(at: at(5000), speed: .oneX)

        // then
        #expect(isRecording(scenario.sut.display))
    }

    @Test func `given a mid-hour instant when playback begins then the hour containing it is fetched`() async {
        // given
        let scenario = Scenario(segments: fullHour(from: 3600))

        // when
        await scenario.sut.beginPlayback(at: at(5000), speed: .oneX)

        // then
        #expect(scenario.recordings.lastWindow == TimeRange(start: at(3600), end: at(7200)))
    }

    @Test func `given an hour with no footage when playback begins then the tile keeps its preview material`() async {
        // given
        let scenario = Scenario(segments: [])
        await scenario.loadPreviews(at: at(5000))

        // when
        await scenario.sut.beginPlayback(at: at(5000), speed: .oneX)

        // then
        #expect(isClip(scenario.sut.display))
    }

    @Test func `given an unreachable server when playback begins then the tile keeps its preview material`() async {
        // given
        let scenario = Scenario(recordings: FakeCameraRecordingsRepository(.failure(.unreachable)))
        await scenario.loadPreviews(at: at(5000))

        // when
        await scenario.sut.beginPlayback(at: at(5000), speed: .oneX)

        // then
        #expect(isClip(scenario.sut.display))
    }

    // MARK: - Leaving playback

    @Test func `given a playing tile when playback ends then it returns to its preview material`() async {
        // given
        let scenario = Scenario(segments: fullHour(from: 3600))
        await scenario.loadPreviews(at: at(5000))
        await scenario.sut.beginPlayback(at: at(5000), speed: .oneX)

        // when
        scenario.sut.endPlayback(at: at(5000))

        // then
        #expect(isClip(scenario.sut.display))
    }

    // MARK: - Following the transport

    @Test func `given a playing tile when the clock crosses into the next hour then that hour is fetched`() async {
        // given
        let scenario = Scenario(segments: fullHour(from: 3600))
        await scenario.sut.beginPlayback(at: at(7100), speed: .oneX)

        // when
        scenario.sut.scrub(to: at(7300))
        await settle { scenario.recordings.lastWindow == TimeRange(start: at(7200), end: at(10_800)) }

        // then
        #expect(scenario.recordings.lastWindow == TimeRange(start: at(7200), end: at(10_800)))
    }

    @Test func `given a playing tile when the clock moves inside the loaded hour then it does not refetch`() async {
        // given
        let scenario = Scenario(segments: fullHour(from: 3600))
        await scenario.sut.beginPlayback(at: at(5000), speed: .oneX)
        let fetches = scenario.recordings.fetchCount

        // when
        scenario.sut.scrub(to: at(5060))
        await settle { false }

        // then
        #expect(scenario.recordings.fetchCount == fetches)
    }

    @Test func `given a playing tile when its scrub material refreshes then the stream stays on screen`() async {
        // given
        let scenario = Scenario(segments: fullHour(from: 3600))
        await scenario.sut.beginPlayback(at: at(5000), speed: .oneX)

        // when — the live edge grows and the tile refreshes its preview material underneath
        await scenario.sut.followLiveEdge(to: previewRange, at: at(5000))

        // then
        #expect(isRecording(scenario.sut.display))
    }

    @Test func `given a tile whose first load lands after playback started then the stream is not replaced`() async {
        // given — a tile appearing while the transport already runs: its first preview load is
        // still in flight when playback takes the display
        let previews = FakeCameraPreviewProvider(clips: [previewClip], frames: [])
        let gate = Gate()
        previews.onClips = { await gate.wait() }
        let scenario = Scenario(previews: previews, segments: fullHour(from: 3600))
        async let firstLoad: Void = scenario.sut.prepare(range: previewRange, at: at(5000))
        await Task.yield()

        // when
        await scenario.sut.beginPlayback(at: at(5000), speed: .oneX)
        await gate.open()
        await firstLoad

        // then
        #expect(isRecording(scenario.sut.display))
    }

    @Test func `given a paused tile when the clock moves then it seeks its preview material`() async {
        // given
        let scenario = Scenario(segments: fullHour(from: 3600))
        await scenario.loadPreviews(at: at(5000))

        // when
        scenario.sut.scrub(to: at(5060))
        await settle { false }

        // then
        #expect(isClip(scenario.sut.display))
        #expect(scenario.recordings.fetchCount == 0)
    }
}

@MainActor
private struct Scenario {
    let recordings: FakeCameraRecordingsRepository
    let previews: FakeCameraPreviewProvider
    let sut: PreviewTileViewModel

    init(previews: FakeCameraPreviewProvider, recordings: FakeCameraRecordingsRepository) {
        self.previews = previews
        self.recordings = recordings
        sut = PreviewTileViewModel(
            camera: camera,
            previews: GetCameraPreviews(provider: previews),
            recordings: GetCameraRecordings(repository: recordings),
            imageLoader: FakePreviewImageLoader(image: nil)
        )
    }

    init(recordings: FakeCameraRecordingsRepository) {
        self.init(previews: FakeCameraPreviewProvider(clips: [previewClip], frames: []), recordings: recordings)
    }

    init(segments: [RecordingSegment]) {
        self.init(recordings: FakeCameraRecordingsRepository(.success(segments)))
    }

    init(previews: FakeCameraPreviewProvider, segments: [RecordingSegment]) {
        self.init(previews: previews, recordings: FakeCameraRecordingsRepository(.success(segments)))
    }

    /// Brings the tile up on its scrub material, the way the grid does before anything is played.
    func loadPreviews(at instant: Date) async {
        await sut.prepare(range: previewRange, at: instant)
    }
}

private let camera = Camera(name: CameraName("driveway"), friendlyName: "Driveway", isEnabled: true, streamNames: ["driveway"])
private let previewRange = TimeRange(start: at(0), end: at(10_800))
private let previewClip = PreviewClip(camera: camera.name, range: previewRange, path: "/preview.mp4")

private func segment(from start: TimeInterval, to end: TimeInterval) -> RecordingSegment {
    RecordingSegment(range: TimeRange(start: at(start), end: at(end)), duration: end - start)
}

/// Unbroken footage in five-minute segments — short enough that the server serves every one of
/// them, so the whole hour is playable.
private func fullHour(from start: TimeInterval) -> [RecordingSegment] {
    stride(from: start, to: start + 3600, by: 300).map { segment(from: $0, to: $0 + 300) }
}

private func isRecording(_ display: PreviewTileViewModel.Display) -> Bool {
    if case .recording = display { true } else { false }
}

private func isClip(_ display: PreviewTileViewModel.Display) -> Bool {
    if case .clip = display { true } else { false }
}

/// A one-shot async gate: `wait()` suspends until `open()` is called. Lets a test hold a fake fetch
/// in flight while something else runs, then release it.
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

/// Spins the main actor until `condition` holds — a window swap hops through a `Task`. Bounded so a
/// never-satisfied expectation fails fast rather than hanging; pass a false condition to simply let
/// any pending work run.
@MainActor
private func settle(_ condition: () -> Bool) async {
    for _ in 0..<100 where !condition() {
        await Task.yield()
    }
}

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
