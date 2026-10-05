import AVFoundation
import Foundation
import Observation
import SwiftUI
import Testing

@testable import CommonPlayer

@MainActor
struct LivePlayerModelTests {

    // MARK: Playback failures

    @Test func `given picture in picture is starting when the screen closes then playback survives until the result`() throws {
        // given
        let scenario = Scenario()
        scenario.sut.start()
        let item = try #require(scenario.sut.player.currentItem)
        scenario.sut.setPictureInPictureStarting()
        defer { scenario.sut.setPictureInPictureActive(false) }

        // when
        scenario.sut.stop()

        // then
        #expect(scenario.sut.player.currentItem === item)
        #expect(scenario.sut.isPlaying)

        // when startup fails
        scenario.sut.setPictureInPictureActive(false)
        scenario.sut.stop()

        // then
        #expect(scenario.sut.player.currentItem == nil)
    }

    @Test(.timeLimit(.minutes(1))) func `given intended playback when the native player pauses then waiting is bounded again`() async throws {
        // given
        let wait = FakePlaybackWait()
        let scenario = Scenario(wait: wait.wait)
        defer {
            scenario.sut.stop()
            wait.elapse()
        }
        let item = try #require(scenario.sut.player.currentItem)
        scenario.sut.start()
        let nativeStatuses = AsyncStream<AVPlayer.TimeControlStatus>.makeStream()
        let observation = scenario.sut.player.observe(\.timeControlStatus, options: [.initial, .new]) { player, _ in
            nativeStatuses.continuation.yield(player.timeControlStatus)
        }
        defer { observation.invalidate() }
        for await status in nativeStatuses.stream {
            if status == .waitingToPlayAtSpecifiedRate { break }
        }
        scenario.sut.handlePlaybackStatus(.playing, for: item)

        // when
        await confirmation("Native playback observation reports waiting") { waiting in
            let changes = AsyncStream<Void>.makeStream()
            withObservationTracking {
                _ = scenario.sut.state
            } onChange: {
                waiting()
                changes.continuation.yield(())
                changes.continuation.finish()
            }
            scenario.sut.player.pause()
            for await _ in changes.stream { break }
        }

        // then
        #expect(scenario.sut.state == .loading)
        #expect(scenario.sut.playbackDeadline != nil)
    }

    @Test func `given a live stream when its item fails then playback shows a failure`() throws {
        // given
        let scenario = Scenario()
        scenario.sut.start()
        let item = try #require(scenario.sut.player.currentItem)

        // when
        NotificationCenter.default.post(
            name: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: NSError(domain: NSURLErrorDomain, code: -1009)]
        )

        // then
        #expect(scenario.sut.isPlaying == false)
    }

    @Test func `given a failed muted stream when retrying then a fresh item loads with mute preserved`() throws {
        // given
        let scenario = Scenario()
        scenario.sut.start()
        scenario.sut.toggleMute()
        let failed = try #require(scenario.sut.player.currentItem)
        NotificationCenter.default.post(name: AVPlayerItem.failedToPlayToEndTimeNotification, object: failed)

        // when
        scenario.sut.retry()

        // then
        #expect(scenario.sut.player.currentItem !== failed)
        #expect(scenario.sut.state == .loading)
        #expect(scenario.sut.isPlaying)
        #expect(scenario.sut.player.isMuted)
    }

    @Test func `given a stream that never starts when the playback deadline expires then it shows a failure`() async {
        // given
        let wait = FakePlaybackWait()
        let scenario = Scenario(wait: wait.wait)
        var requests = wait.requests.makeAsyncIterator()
        scenario.sut.start()
        let deadline = scenario.sut.playbackDeadline
        let duration = await requests.next()

        // when
        wait.elapse()
        await deadline?.value

        // then
        #expect(duration == .seconds(15))
        #expect(scenario.sut.state == .failed)
        #expect(scenario.sut.isPlaying == false)
    }

    @Test func `given a loading stream when paused then its waiting deadline is cancelled`() throws {
        // given
        let scenario = Scenario()
        scenario.sut.start()
        let deadline = try #require(scenario.sut.playbackDeadline)

        // when
        scenario.sut.togglePlayPause()

        // then
        #expect(deadline.isCancelled)
        #expect(scenario.sut.state == .paused)
    }

    @Test func `given a loading stream when backgrounded then its waiting deadline is cancelled`() throws {
        // given
        let scenario = Scenario()
        scenario.sut.start()
        let deadline = try #require(scenario.sut.playbackDeadline)

        // when
        scenario.sut.handleScenePhase(.background)

        // then
        #expect(deadline.isCancelled)
        #expect(scenario.sut.isPlaying)
    }

    @Test func `given a waiting stream when retrying then the old deadline is cancelled and a new one begins`() throws {
        // given
        let scenario = Scenario()
        scenario.sut.start()
        let deadline = try #require(scenario.sut.playbackDeadline)

        // when
        scenario.sut.retry()

        // then
        #expect(deadline.isCancelled)
        #expect(scenario.sut.playbackDeadline?.isCancelled == false)
        #expect(scenario.sut.state == .loading)
    }

    @Test func `given a loading stream when actual playback starts then the waiting deadline ends`() throws {
        // given
        let scenario = Scenario()
        scenario.sut.start()
        let item = try #require(scenario.sut.player.currentItem)
        let deadline = try #require(scenario.sut.playbackDeadline)

        // when
        scenario.sut.handlePlaybackStatus(.playing, for: item)

        // then
        #expect(scenario.sut.state == .playing)
        #expect(deadline.isCancelled)
    }

    @Test func `given a live stream when the item status fails then playback exposes the failure immediately`() throws {
        // given
        let scenario = Scenario()
        scenario.sut.start()
        let item = try #require(scenario.sut.player.currentItem)

        // when
        scenario.sut.handleItemStatus(.failed, for: item)

        // then
        #expect(scenario.sut.state == .failed)
        #expect(scenario.sut.isPlaying == false)
    }

    @Test func `given a loading stream when paused and resumed then waiting is bounded again`() async throws {
        // given
        let wait = FakePlaybackWait()
        let scenario = Scenario(wait: wait.wait)
        var requests = wait.requests.makeAsyncIterator()
        scenario.sut.start()
        _ = await requests.next()
        scenario.sut.togglePlayPause()

        // when
        scenario.sut.togglePlayPause()
        let deadline = try #require(scenario.sut.playbackDeadline)
        _ = await requests.next()
        wait.elapse()
        await deadline.value

        // then
        #expect(scenario.sut.state == .failed)
        #expect(scenario.sut.isPlaying == false)
    }

    @Test func `given a playing stream when playback stalls past the deadline then it shows a failure`() async throws {
        // given
        let wait = FakePlaybackWait()
        let scenario = Scenario(wait: wait.wait)
        var requests = wait.requests.makeAsyncIterator()
        scenario.sut.start()
        _ = await requests.next()
        let item = try #require(scenario.sut.player.currentItem)
        scenario.sut.handlePlaybackStatus(.playing, for: item)

        // when
        scenario.sut.handlePlaybackStatus(.waitingToPlayAtSpecifiedRate, for: item)
        let deadline = try #require(scenario.sut.playbackDeadline)
        _ = await requests.next()
        wait.elapse()
        await deadline.value

        // then
        #expect(scenario.sut.state == .failed)
    }

    @Test func `given an inline stream when its screen closes then the item and waiting work are released`() throws {
        // given
        let scenario = Scenario()
        scenario.sut.start()
        let deadline = try #require(scenario.sut.playbackDeadline)

        // when
        scenario.sut.stop()

        // then
        #expect(scenario.sut.player.currentItem == nil)
        #expect(deadline.isCancelled)
        #expect(scenario.sut.isPlaying == false)
    }

    @Test func `given a stopped stream when its screen reopens then a fresh live item begins loading`() {
        // given
        let scenario = Scenario()
        scenario.sut.start()
        scenario.sut.stop()

        // when
        scenario.sut.start()

        // then
        #expect(scenario.sut.player.currentItem != nil)
        #expect(scenario.sut.state == .loading)
        #expect(scenario.sut.isPlaying)
    }

    @Test func `given an active picture in picture session when the screen closes then playback is retained`() {
        // given
        let scenario = Scenario()
        scenario.sut.start()
        scenario.sut.setPictureInPictureActive(true)
        defer { scenario.sut.setPictureInPictureActive(false) }
        let item = scenario.sut.player.currentItem

        // when
        scenario.sut.stop()

        // then
        #expect(scenario.sut.player.currentItem === item)
        #expect(scenario.sut.isPlaying)
    }

    @Test func `given a replacement stream when the old item reports playback or failure then the new stream is unchanged`() throws {
        // given
        let scenario = Scenario()
        scenario.sut.start()
        let stale = try #require(scenario.sut.player.currentItem)
        scenario.sut.retry()
        let current = scenario.sut.player.currentItem

        // when
        scenario.sut.handleItemStatus(.failed, for: stale)
        scenario.sut.handlePlaybackStatus(.playing, for: stale)
        NotificationCenter.default.post(name: AVPlayerItem.failedToPlayToEndTimeNotification, object: stale)

        // then
        #expect(scenario.sut.state == .loading)
        #expect(scenario.sut.player.currentItem === current)
        #expect(scenario.sut.isPlaying)
    }

    @Test func `given a playing replacement stream when a released item reports waiting then playback and its deadline are unchanged`() throws {
        // given
        let scenario = Scenario()
        scenario.sut.start()
        scenario.sut.retry()
        defer { scenario.sut.stop() }
        let current = try #require(scenario.sut.player.currentItem)
        scenario.sut.handlePlaybackStatus(.playing, for: current)
        weak var released: AVPlayerItem?
        do {
            let original = AVPlayerItem(asset: AVMutableComposition())
            released = original
        }
        try #require(released == nil)

        // when
        scenario.sut.handlePlaybackStatus(.waitingToPlayAtSpecifiedRate, for: released)

        // then
        #expect(scenario.sut.state == .playing)
        #expect(scenario.sut.isPlaying)
        #expect(scenario.sut.player.currentItem === current)
        #expect(scenario.sut.playbackDeadline == nil)
    }

    @Test func `given a replacement stream when an old waiting deadline finishes then the new stream keeps loading`() async throws {
        // given
        let wait = FakePlaybackWait()
        let scenario = Scenario(wait: wait.wait)
        var requests = wait.requests.makeAsyncIterator()
        scenario.sut.start()
        _ = await requests.next()
        let stale = try #require(scenario.sut.playbackDeadline)
        scenario.sut.retry()
        scenario.keepCurrentAssetLoading()
        _ = await requests.next()

        // when
        wait.elapseNext()
        await stale.value

        // then
        #expect(scenario.sut.state == .loading)
        #expect(scenario.sut.isPlaying)
        let current = scenario.sut.playbackDeadline
        wait.elapse()
        await current?.value
    }

    @Test func `given a loading stream when audio is interrupted then waiting is cancelled until the interruption ends`() throws {
        // given
        let scenario = Scenario()
        scenario.sut.start()
        let item = try #require(scenario.sut.player.currentItem)
        let deadline = try #require(scenario.sut.playbackDeadline)

        // when
        scenario.sut.handleAudioInterruption(.began)
        scenario.sut.handlePlaybackStatus(.waitingToPlayAtSpecifiedRate, for: item)

        // then
        #expect(deadline.isCancelled)
        #expect(scenario.sut.playbackDeadline == nil)
        #expect(scenario.sut.isPlaying)
    }

    @Test func `given a user pause during an audio interruption when it ends then playback stays paused`() {
        // given
        let scenario = Scenario()
        scenario.sut.start()
        scenario.sut.handleAudioInterruption(.began)
        scenario.sut.togglePlayPause()
        let item = scenario.sut.player.currentItem

        // when
        scenario.sut.handleAudioInterruption(.ended)

        // then
        #expect(scenario.sut.isPlaying == false)
        #expect(scenario.sut.state == .paused)
        #expect(scenario.sut.player.currentItem === item)
    }

    // MARK: Returning from the background

    @Test func `given a playing stream when the app returns from the background then it plays a fresh live item`() {
        // given
        let sut = liveModel()
        sut.start()
        let stale = sut.player.currentItem

        // when
        sut.handleScenePhase(.background)
        sut.handleScenePhase(.inactive)
        sut.handleScenePhase(.active)

        // then
        #expect(sut.player.currentItem !== stale)
        #expect(sut.isPlaying)
    }

    @Test func `given a playing stream when the app only loses focus then it keeps the live item`() {
        // given
        let sut = liveModel()
        sut.start()
        let item = sut.player.currentItem

        // when
        sut.handleScenePhase(.inactive)
        sut.handleScenePhase(.active)

        // then
        #expect(sut.player.currentItem === item)
        #expect(sut.isPlaying)
    }

    @Test func `given a paused stream when the app returns from the background then it stays paused on the same item`() {
        // given
        let sut = liveModel()
        sut.start()
        sut.togglePlayPause()
        let item = sut.player.currentItem

        // when
        sut.handleScenePhase(.background)
        sut.handleScenePhase(.active)

        // then
        #expect(sut.player.currentItem === item)
        #expect(sut.isPlaying == false)
    }

    // MARK: Resuming from pause

    @Test func `given a stream paused across a background when playing again then it plays a fresh live item`() {
        // given
        let sut = liveModel()
        sut.start()
        sut.togglePlayPause()
        sut.handleScenePhase(.background)
        sut.handleScenePhase(.active)
        let stale = sut.player.currentItem

        // when
        sut.togglePlayPause()

        // then
        #expect(sut.player.currentItem !== stale)
        #expect(sut.isPlaying)
    }

    @Test func `given a stream paused with the app in the foreground when playing again then it keeps the live item`() {
        // given
        let sut = liveModel()
        sut.start()
        sut.togglePlayPause()
        let item = sut.player.currentItem

        // when
        sut.togglePlayPause()

        // then
        #expect(sut.player.currentItem === item)
        #expect(sut.isPlaying)
    }

    @MainActor
    private struct Scenario {
        let sut: LivePlayerModel
        let assetLoader = FakePendingLiveAssetLoader()

        init(
            url: URL = URL(string: "aura-test://live/stream.m3u8")!,
            wait: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
        ) {
            sut = LivePlayerModel(
                url: url,
                headers: ["Authorization": "Basic ZHJpdmV3YXk="],
                waitForPlayback: wait
            )
            keepCurrentAssetLoading()
        }

        func keepCurrentAssetLoading() {
            let asset = sut.player.currentItem?.asset as? AVURLAsset
            #expect(asset != nil)
            asset?.resourceLoader.setDelegate(assetLoader, queue: .main)
        }
    }
}

private final class FakePendingLiveAssetLoader: NSObject, AVAssetResourceLoaderDelegate {
    nonisolated func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        // Keep native loading pending so state-machine tests cannot race a real DNS failure.
        true
    }
}

@MainActor
private func liveModel() -> LivePlayerModel {
    LivePlayerModel(
        url: URL(string: "http://frigate.test:1984/api/stream.m3u8?src=driveway")!,
        headers: ["Authorization": "Basic ZHJpdmV3YXk="]
    )
}
