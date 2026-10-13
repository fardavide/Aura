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

    @Test(arguments: [PlaybackSpeed.fourX, .eightX])
    func `given fast forward when playback begins then the bounded two minute window is fetched`(speed: PlaybackSpeed) async {
        // given
        let scenario = Scenario(segments: fullHour(from: 3600))

        // when
        await scenario.sut.beginPlayback(at: at(5000), speed: speed)

        // then
        #expect(scenario.recordings.lastWindow == TimeRange(start: at(4920), end: at(5040)))
    }

    @Test(arguments: [PlaybackSpeed.oneX, .twoX])
    func `given a fast forward tile when selecting a low speed then its hour recording source is restored`(speed: PlaybackSpeed) async throws {
        // given
        let scenario = Scenario(segments: fullHour(from: 3600))
        let fixture = try #require(Bundle.module.url(forResource: "recording", withExtension: "mp4", subdirectory: "Fixtures"))
        scenario.recordings.clipsResult = .success([
            RecordingClip(
                source: CameraStreamSource(url: fixture, headers: [:]),
                range: TimeRange(start: at(5000), end: at(5002)),
                sourceOffset: 0,
                duration: 2
            ),
        ])
        await scenario.sut.beginPlayback(at: at(5000), speed: .fourX)

        // when
        scenario.sut.select(speed)
        for _ in 0..<10_000 {
            if scenario.recordings.fetchCount >= 2,
               case let .recording(player) = scenario.sut.display,
               (player.currentItem?.asset as? AVURLAsset)?.url == scenario.recordings.source.url { break }
            await Task.yield()
        }

        // then
        #expect(scenario.recordings.fetchCount == 2)
        #expect(scenario.recordings.lastWindow == TimeRange(start: at(3600), end: at(7200)))
        guard case let .recording(player) = scenario.sut.display else {
            Issue.record("Expected the tile to play the hour recording")
            return
        }
        let asset = try #require(player.currentItem?.asset as? AVURLAsset)
        #expect(asset.url == scenario.recordings.source.url)
    }

    @Test func `given a pending fast forward tile when a newer low speed is selected then the late start cannot replace the hour source`() async throws {
        // given
        let scenario = Scenario(segments: fullHour(from: 3600))
        let fixture = try #require(Bundle.module.url(forResource: "recording", withExtension: "mp4", subdirectory: "Fixtures"))
        scenario.recordings.clipsResult = .success([
            RecordingClip(
                source: CameraStreamSource(url: fixture, headers: [:]),
                range: TimeRange(start: at(5000), end: at(5002)),
                sourceOffset: 0,
                duration: 2
            ),
        ])
        let gate = Gate()
        scenario.recordings.onSegments = { call in
            if call == 1 { await gate.wait() }
        }
        let start = Task { await scenario.sut.beginPlayback(at: at(5000), speed: .fourX) }
        for _ in 0..<10_000 where scenario.recordings.fetchCount < 1 {
            await Task.yield()
        }

        // when
        scenario.sut.select(.twoX)
        await gate.open()
        await start.value
        for _ in 0..<10_000 {
            if scenario.recordings.fetchCount >= 2,
               case let .recording(player) = scenario.sut.display,
               (player.currentItem?.asset as? AVURLAsset)?.url == scenario.recordings.source.url { break }
            await Task.yield()
        }

        // then
        #expect(scenario.recordings.fetchCount == 2)
        #expect(scenario.recordings.lastWindow == TimeRange(start: at(3600), end: at(7200)))
        guard case let .recording(player) = scenario.sut.display else {
            Issue.record("Expected the tile to play the newer hour source")
            return
        }
        let asset = try #require(player.currentItem?.asset as? AVURLAsset)
        #expect(asset.url == scenario.recordings.source.url)
    }

    @Test func `given a fast forward clip that cannot load when the clock ticks inside its window then the failed window is not fetched again`() async {
        // given
        let scenario = Scenario(segments: fullHour(from: 3600))
        await scenario.loadPreviews(at: at(5000))
        scenario.recordings.clipsResult = .success([
            RecordingClip(
                source: CameraStreamSource(url: URL(filePath: "/missing-fast-forward-recording.mp4"), headers: [:]),
                range: TimeRange(start: at(5000), end: at(5002)),
                sourceOffset: 0,
                duration: 2
            ),
        ])
        await scenario.sut.beginPlayback(at: at(5000), speed: .fourX)
        let fetches = scenario.recordings.fetchCount

        // when
        for instant in [at(5001), at(5002), at(5003)] {
            scenario.sut.scrub(to: instant)
            for _ in 0..<1000 { await Task.yield() }
        }

        // then
        #expect(scenario.recordings.fetchCount == fetches)
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

    @Test func `given a loaded four times tile when selecting eight times speed then its media item is reused`() async throws {
        // given
        let scenario = Scenario(segments: fullHour(from: 3600))
        let fixture = try #require(Bundle.module.url(forResource: "recording", withExtension: "mp4", subdirectory: "Fixtures"))
        scenario.recordings.clipsResult = .success([
            RecordingClip(
                source: CameraStreamSource(url: fixture, headers: [:]),
                range: TimeRange(start: at(5000), end: at(5002)),
                sourceOffset: 0,
                duration: 2
            ),
        ])
        await scenario.sut.beginPlayback(at: at(5000), speed: .fourX)
        guard case let .recording(player) = scenario.sut.display else {
            Issue.record("Expected the fast forward tile to be ready")
            return
        }
        let item = try #require(player.currentItem)
        let fetches = scenario.recordings.fetchCount

        // when
        scenario.sut.select(.eightX)
        for _ in 0..<100 { await Task.yield() }

        // then
        #expect(item.asset is AVComposition)
        #expect(scenario.recordings.fetchCount == fetches)
        guard case let .recording(currentPlayer) = scenario.sut.display else {
            Issue.record("Expected the fast forward tile to remain ready")
            return
        }
        #expect(currentPlayer.currentItem === item)
    }

    @Test func `given continuous fast forward footage when the clock approaches the window end then the following window starts loading before current footage ends`() async throws {
        // given
        let scenario = Scenario(segments: fullHour(from: 3600))
        let fixture = try #require(Bundle.module.url(forResource: "recording", withExtension: "mp4", subdirectory: "Fixtures"))
        let source = CameraStreamSource(url: fixture, headers: [:])
        scenario.recordings.clipsForWindow = { window in
            .success(stride(from: window.start.timeIntervalSince1970, to: window.end.timeIntervalSince1970, by: 2).map { start in
                RecordingClip(
                    source: source,
                    range: TimeRange(start: at(start), end: at(start + 2)),
                    sourceOffset: 0,
                    duration: 2
                )
            })
        }
        await scenario.sut.beginPlayback(at: at(4920), speed: .eightX)
        guard case let .recording(player) = scenario.sut.display else {
            Issue.record("Expected the current fast forward footage before approaching its boundary")
            return
        }
        try #require(player.currentItem?.asset is AVComposition)
        player.pause()
        let gate = Gate()
        scenario.recordings.onSegments = { call in
            if call == 2 { await gate.wait() }
        }

        // when — the transport still has one second of footage in the current window.
        scenario.sut.scrub(to: at(5039))
        for _ in 0..<10_000 where scenario.recordings.fetchCount < 2 { await Task.yield() }
        let requestedWindow = scenario.recordings.lastWindow
        scenario.sut.endPlayback(at: at(5039))
        await gate.open()

        // then
        #expect(requestedWindow == TimeRange(start: at(5040), end: at(5160)))
    }

    @Test func `given a growing following window when the transport approaches its boundary then speculative loading is deferred`() async throws {
        // given
        let recordings = FakeCameraRecordingsRepository(.success(fullHour(from: 3600)))
        let sut = PreviewTileViewModel(
            camera: camera,
            previews: GetCameraPreviews(provider: FakeCameraPreviewProvider(clips: [], frames: [])),
            recordings: GetCameraRecordings(repository: recordings),
            imageLoader: FakePreviewImageLoader(image: nil),
            now: { at(5041) }
        )
        let fixture = try #require(Bundle.module.url(forResource: "recording", withExtension: "mp4", subdirectory: "Fixtures"))
        let source = CameraStreamSource(url: fixture, headers: [:])
        recordings.clipsForWindow = { window in
            .success(stride(from: window.start.timeIntervalSince1970, to: window.end.timeIntervalSince1970, by: 2).map { start in
                RecordingClip(source: source, range: TimeRange(start: at(start), end: at(start + 2)), sourceOffset: 0, duration: 2)
            })
        }
        await sut.beginPlayback(at: at(4920), speed: .eightX)
        guard case let .recording(player) = sut.display else {
            Issue.record("Expected the current recording composition")
            return
        }
        player.pause()

        // when
        sut.scrub(to: at(5039))
        for _ in 0..<100 { await Task.yield() }
        let fetchCount = recordings.fetchCount
        sut.endPlayback(at: at(5039))

        // then
        #expect(fetchCount == 1)
    }

    @Test func `given a pending continuous fast forward window when the clock crosses its boundary then playback uses it without fetching it again`() async throws {
        // given
        let scenario = Scenario(segments: fullHour(from: 3600))
        let fixture = try #require(Bundle.module.url(forResource: "recording", withExtension: "mp4", subdirectory: "Fixtures"))
        let source = CameraStreamSource(url: fixture, headers: [:])
        scenario.recordings.clipsForWindow = { window in
            .success(stride(from: window.start.timeIntervalSince1970, to: window.end.timeIntervalSince1970, by: 2).map { start in
                RecordingClip(
                    source: source,
                    range: TimeRange(start: at(start), end: at(start + 2)),
                    sourceOffset: 0,
                    duration: 2
                )
            })
        }
        await scenario.sut.beginPlayback(at: at(4920), speed: .eightX)
        guard case let .recording(initialPlayer) = scenario.sut.display else {
            Issue.record("Expected the current fast forward footage before its boundary")
            return
        }
        let initialItem = try #require(initialPlayer.currentItem)
        try #require(initialItem.asset is AVComposition)
        initialPlayer.pause()
        let gate = Gate()
        scenario.recordings.onSegments = { call in
            if call == 2 { await gate.wait() }
        }
        scenario.sut.scrub(to: at(5039))
        for _ in 0..<10_000 where scenario.recordings.fetchCount < 2 { await Task.yield() }
        try #require(scenario.recordings.lastWindow == TimeRange(start: at(5040), end: at(5160)))

        // when
        scenario.sut.scrub(to: at(5040))
        await gate.open()
        for _ in 0..<10_000 {
            if case let .recording(player) = scenario.sut.display,
               player.currentItem !== initialItem,
               player.currentItem?.asset is AVComposition { break }
            await Task.yield()
        }

        // then
        guard case let .recording(player) = scenario.sut.display else {
            Issue.record("Expected the following fast forward window to play")
            return
        }
        try #require(player.currentItem !== initialItem)
        try #require(player.currentItem?.asset is AVComposition)
        #expect(scenario.recordings.fetchCount == 2)
        scenario.sut.endPlayback(at: at(5040))
    }

    @Test func `given a fast forward tile when the clock reaches the window end then the following two minute window is fetched`() async throws {
        // given
        let scenario = Scenario(segments: fullHour(from: 3600))
        let fixture = try #require(Bundle.module.url(forResource: "recording", withExtension: "mp4", subdirectory: "Fixtures"))
        let source = CameraStreamSource(url: fixture, headers: [:])
        scenario.recordings.clipsResult = .success([
            RecordingClip(source: source, range: TimeRange(start: at(5000), end: at(5002)), sourceOffset: 0, duration: 2),
        ])
        await scenario.sut.beginPlayback(at: at(5000), speed: .fourX)
        guard case let .recording(initialPlayer) = scenario.sut.display else {
            Issue.record("Expected the first fast forward window to be ready")
            return
        }
        let initialItem = try #require(initialPlayer.currentItem)
        scenario.recordings.clipsResult = .success([
            RecordingClip(source: source, range: TimeRange(start: at(5040), end: at(5042)), sourceOffset: 0, duration: 2),
        ])

        // when
        scenario.sut.scrub(to: at(5040))
        for _ in 0..<10_000 {
            if scenario.recordings.fetchCount >= 2,
               case let .recording(player) = scenario.sut.display,
               player.currentItem !== initialItem,
               player.currentItem?.asset is AVComposition { break }
            await Task.yield()
        }

        // then
        #expect(scenario.recordings.fetchCount == 2)
        #expect(scenario.recordings.lastWindow == TimeRange(start: at(5040), end: at(5160)))
        guard case let .recording(player) = scenario.sut.display else {
            Issue.record("Expected the following fast forward window to be ready")
            return
        }
        #expect(player.currentItem !== initialItem)
        #expect(player.currentItem?.asset is AVComposition)
    }

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
