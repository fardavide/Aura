import AVFoundation
import Foundation
import Testing

import CamerasEntities
import TestDoubles
import TimelineDomain
@testable import TimelinePresentation

@MainActor
struct RecordingWindowPreloaderTests {
    @Test func `given original recording clips when the following window is prepared then its native player is ready for a paused handoff`() async throws {
        // given
        let scenario = try Scenario()

        // when
        scenario.sut.prepare(window: scenario.window)
        let prepared = try await scenario.sut.load(window: scenario.window, mode: .fastForward)

        // then
        guard case .playable(_, let player) = prepared else {
            Issue.record("Expected the prepared recording player")
            return
        }
        #expect(player.status == .readyToPlay)
        #expect(player.rate == 0)
    }

    @Test func `given a pending window already being consumed when preparation is requested again then the same fetch is reused`() async throws {
        // given
        let scenario = try Scenario()
        let gate = Gate()
        scenario.recordings.onSegments = { call in
            if call == 1 { await gate.wait() }
        }
        scenario.sut.prepare(window: scenario.window)
        var loadingStarted = false
        let load = Task {
            loadingStarted = true
            return try await scenario.sut.load(window: scenario.window, mode: .fastForward)
        }
        for _ in 0..<10_000 where !loadingStarted { await Task.yield() }
        try #require(loadingStarted)

        // when
        scenario.sut.prepare(window: scenario.window)
        for _ in 0..<100 { await Task.yield() }
        await gate.open()
        _ = try await load.value
        scenario.sut.cancel()

        // then
        #expect(scenario.recordings.fetchCount == 1)
    }

    @Test func `given a speculative fetch failure when its window is needed then a fresh request can recover`() async throws {
        // given
        let scenario = try Scenario()
        scenario.recordings.onSegments = { [recordings = scenario.recordings] call in
            recordings.result = call == 1 ? .failure(.serverUnavailable) : .success([])
        }
        scenario.sut.prepare(window: scenario.window)

        // when
        let prepared = try await scenario.sut.load(window: scenario.window, mode: .fastForward)

        // then
        #expect(scenario.recordings.fetchCount == 2)
        #expect(prepared.recording.timeline.playableDuration == 2)
    }

    @Test func `given two consumers of a failed preload when the fresh request recovers then both receive the recovered window`() async throws {
        // given
        let scenario = try Scenario()
        let failureGate = Gate()
        let recoveryGate = Gate()
        scenario.recordings.onSegments = { [recordings = scenario.recordings] call in
            if call == 1 {
                await failureGate.wait()
                recordings.result = .failure(.serverUnavailable)
            } else {
                await recoveryGate.wait()
                recordings.result = .success([])
            }
        }
        scenario.sut.prepare(window: scenario.window)
        var firstStarted = false
        var secondStarted = false
        let first = Task {
            firstStarted = true
            return try await scenario.sut.load(window: scenario.window, mode: .fastForward)
        }
        let second = Task {
            secondStarted = true
            return try await scenario.sut.load(window: scenario.window, mode: .fastForward)
        }
        for _ in 0..<10_000 where !firstStarted || !secondStarted { await Task.yield() }
        try #require(firstStarted && secondStarted)

        // when
        await failureGate.open()
        for _ in 0..<10_000 where scenario.recordings.fetchCount < 2 { await Task.yield() }
        await recoveryGate.open()
        let firstWindow = try await first.value
        let secondWindow = try await second.value

        // then
        #expect(firstWindow.recording.timeline.playableDuration == 2)
        #expect(secondWindow.recording.timeline.playableDuration == 2)
        #expect(scenario.recordings.fetchCount == 2)
    }

    @Test func `given failed speculative and recovery requests when playback is retried later then it fetches the window again`() async throws {
        // given
        let scenario = try Scenario()
        scenario.recordings.onSegments = { [recordings = scenario.recordings] call in
            recordings.result = call < 3 ? .failure(.serverUnavailable) : .success([])
        }
        scenario.sut.prepare(window: scenario.window)
        do throws(TimelineError) {
            _ = try await scenario.sut.load(window: scenario.window, mode: .fastForward)
            Issue.record("Expected the foreground recovery to report the outage")
        } catch {
            #expect(error == .serverUnavailable)
        }

        // when
        let recovered = try await scenario.sut.load(window: scenario.window, mode: .fastForward)

        // then
        #expect(scenario.recordings.fetchCount == 3)
        #expect(recovered.recording.timeline.playableDuration == 2)
    }

    private actor Gate {
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var isOpen = false

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
    private struct Scenario {
        let recordings: FakeCameraRecordingsRepository
        let sut: RecordingWindowPreloader
        let window: TimeRange

        init() throws {
            let url = try #require(Bundle.module.url(forResource: "recording", withExtension: "mp4", subdirectory: "Fixtures"))
            recordings = FakeCameraRecordingsRepository(.success([]))
            window = TimeRange(start: Date(timeIntervalSince1970: 120), end: Date(timeIntervalSince1970: 240))
            recordings.clipsResult = .success([
                RecordingClip(source: CameraStreamSource(url: url, headers: [:]), range: TimeRange(start: window.start, end: window.start.addingTimeInterval(2)), sourceOffset: 0, duration: 2),
            ])
            sut = RecordingWindowPreloader(camera: CameraName("driveway"), recordings: GetCameraRecordings(repository: recordings))
        }
    }
}
