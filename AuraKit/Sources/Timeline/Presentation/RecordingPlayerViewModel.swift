import AVFoundation
import Foundation
import Observation

import CamerasDomain
import CommonPlayer
import TimelineDomain

/// Full-resolution playback of one camera's recordings, opened from a tile at the instant it was
/// tapped. Unlike the scrub grid's low-res preview material this plays the recorded stream itself,
/// with the transport (play/pause, skip, speed) the Frigate web client offers.
///
/// Playback runs over one bounded window at a time — the server won't serve a whole day in a
/// single playlist — so the model swaps windows underneath the transport whenever a skip runs off
/// one end or the stream plays out. `RecordingTimeline` converts between the wall clock the
/// readout shows and the stream's own clock, which drift apart by exactly the footage that is
/// missing: the stream omits the gaps entirely.
///
/// **Skipping is in stream time, not wall-clock time.** Ten seconds back means ten seconds of
/// footage back, so a skip steps over a gap instead of stalling inside it — which is what a
/// viewer means by the button, and what the player can actually do.
@Observable
@MainActor
public final class RecordingPlayerViewModel {
    public enum Display {
        case loading
        case ready(AVPlayer)
        /// The hour holds no footage at all — the skips stay live so it can be left.
        case noFootage
        case failed
    }

    public let camera: Camera
    public private(set) var display: Display = .loading
    public private(set) var isPlaying = false
    public private(set) var speed: PlaybackSpeed = .oneX
    /// The wall-clock instant under the playhead — what the readout shows, and what a window swap
    /// re-seeks to on the other side.
    public private(set) var instant: Date
    /// Whether the playhead sits over recorded footage. False inside a gap, where the stream shows
    /// the next recorded moment instead — worth saying rather than silently showing the wrong time.
    public private(set) var hasFootage = false

    private let recordings: GetCameraRecordings
    private let now: @MainActor () -> Date
    private var window: TimeRange
    private var timeline: RecordingTimeline
    /// Stamps each window load so one that lands after a newer request — a second skip, or a seek
    /// the user made while it was in flight — is dropped instead of yanking the playhead back.
    private var loadGeneration = 0
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?

    public init(
        camera: Camera,
        recordings: GetCameraRecordings,
        now: @escaping @MainActor () -> Date,
        startingAt instant: Date
    ) {
        self.camera = camera
        self.recordings = recordings
        self.now = now
        self.instant = instant
        let initial = RecordingWindow.containing(instant)
        window = initial
        timeline = RecordingTimeline(window: initial, segments: [])
    }

    isolated deinit {
        detachPlayer()
    }

    /// Loads on first appearance only, so returning to the screen doesn't restart the recording.
    public func loadIfNeeded() async {
        guard case .loading = display else { return }
        isPlaying = true
        await load(window: window, seeking: .instant(instant))
    }

    public func togglePlayPause() {
        setPlaying(!isPlaying)
    }

    public func select(_ speed: PlaybackSpeed) {
        self.speed = speed
        guard isPlaying else { return }
        player?.rate = speed.rate
    }

    /// Moves the playhead by `seconds` **of footage**. Running off the end of the window continues
    /// into the neighbouring hour; running off the newest footage does nothing, because there is
    /// nothing recorded past it yet.
    public func skip(by seconds: TimeInterval) async {
        // A seek is a newer intent than any load still in flight — let it win.
        loadGeneration += 1
        let target = timeline.playerTime(at: instant) + seconds
        if target < 0 {
            let previous = RecordingWindow.containing(window.start.addingTimeInterval(-1))
            await load(window: previous, seeking: .latestFootage)
        } else if target > timeline.playableDuration {
            await loadFollowingWindow()
        } else {
            seek(toPlayerTime: target)
        }
    }

    /// The stream played out. Continues into the next hour, or stops — nothing after the newest
    /// footage has been recorded yet, so this is the live edge.
    func advanceToNextWindow() async {
        if await loadFollowingWindow() { return }
        setPlaying(false)
    }

    /// Loads the hour after the current one. Answers `false` without touching anything when that
    /// hour hasn't happened yet, which is how the live edge is recognised.
    @discardableResult
    private func loadFollowingWindow() async -> Bool {
        let next = RecordingWindow.containing(window.end)
        guard next.start < now() else { return false }
        await load(window: next, seeking: .instant(next.start))
        return true
    }

    private func load(window newWindow: TimeRange, seeking target: SeekTarget) async {
        loadGeneration += 1
        let generation = loadGeneration
        let playback: RecordingPlayback
        do {
            playback = try await recordings.execute(for: camera.name, in: newWindow)
        } catch {
            // A torn-down fetch (the screen was left) is not a server failure — leave the state
            // for whatever replaces it rather than flashing an error on the way out.
            if Task.isCancelled || generation != loadGeneration { return }
            // Tear the old player down first: the error screen hides the transport, so a player
            // left running would keep streaming — and keep moving the playhead — unstoppably.
            detachPlayer()
            display = .failed
            isPlaying = false
            return
        }
        guard generation == loadGeneration else { return }
        window = newWindow
        timeline = playback.timeline
        detachPlayer()

        guard timeline.playableDuration > 0 else {
            apply(instant: resolve(target))
            display = .noFootage
            isPlaying = false
            return
        }
        let player = makeAuthedPlayer(url: playback.source.url, headers: playback.source.headers)
        attach(player, playing: newWindow)
        display = .ready(player)
        seek(toPlayerTime: timeline.playerTime(at: resolve(target)))
        // Read the intent now rather than capturing it at call time: a play/pause taken while the
        // fetch was in flight is the newer one and must not be reverted.
        setPlaying(isPlaying)
    }

    private func resolve(_ target: SeekTarget) -> Date {
        switch target {
        case .instant(let instant): instant
        case .latestFootage: timeline.instant(atPlayerTime: timeline.playableDuration)
        }
    }

    private func seek(toPlayerTime playerTime: TimeInterval) {
        let clamped = min(max(playerTime, 0), timeline.playableDuration)
        apply(instant: timeline.instant(atPlayerTime: clamped))
        // Exact: a tolerant seek would land on a keyframe seconds away, and the readout — driven
        // by the player's own clock — would then disagree with the instant that was asked for.
        player?.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func apply(instant: Date) {
        self.instant = instant
        hasFootage = timeline.hasFootage(at: instant)
    }

    /// Drives the rate rather than `play()`/`pause()` so resuming picks the chosen speed back up
    /// in one step instead of briefly running at 1×.
    private func setPlaying(_ playing: Bool) {
        isPlaying = playing
        player?.rate = playing ? speed.rate : 0
    }

    private func attach(_ player: AVPlayer, playing playedWindow: TimeRange) {
        self.player = player
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, time.seconds.isFinite else { return }
                self.apply(instant: self.timeline.instant(atPlayerTime: time.seconds))
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Removing the observer doesn't recall a block already queued on the main queue,
                // so an end posted just before a window swap could otherwise advance a second time.
                guard let self, self.window == playedWindow else { return }
                Task { await self.advanceToNextWindow() }
            }
        }
    }

    private func detachPlayer() {
        if let player, let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        timeObserver = nil
        endObserver = nil
        player?.rate = 0
        player = nil
    }
}

/// Where a freshly loaded window should open. `latestFootage` can't be named as an instant by the
/// caller — it is only known once that window's footage has been fetched.
private enum SeekTarget {
    case instant(Date)
    case latestFootage
}
