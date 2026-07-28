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
    /// The history the scrub track covers: `[start, now]`. The start is fixed for the screen's
    /// life; a refresh only extends the end to the present.
    public private(set) var span: TimeRange
    /// This camera's activity over `span` — the markers, motion and gaps the track draws.
    public private(set) var dayTimeline = DayTimeline(markers: [], motion: [], gaps: [])
    /// The density the track is drawn at.
    public private(set) var zoom: TimelineZoom = .hour

    /// Everything the layout renders, as one value — the screen's chrome is a pure function of it,
    /// which is what lets every arrangement be screenshot-tested without a player.
    public var state: RecordingDetailState {
        RecordingDetailState(
            cameraName: camera.friendlyName ?? camera.name.value,
            instant: instant,
            span: span,
            dayTimeline: dayTimeline,
            zoom: zoom,
            isPlaying: isPlaying,
            speed: speed,
            hasFootage: hasFootage,
            isPlayable: isPlayable
        )
    }

    /// Whether there is anything to start or speed up. An hour holding no footage isn't playable,
    /// though the skips and the track stay live so it can be left.
    private var isPlayable: Bool {
        switch display {
        case .ready: true
        case .loading, .noFootage, .failed: false
        }
    }

    private let recordings: GetCameraRecordings
    private let getDayTimeline: GetDayTimeline
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
        getDayTimeline: GetDayTimeline,
        now: @escaping @MainActor () -> Date,
        startingAt instant: Date,
        days: Int
    ) {
        self.camera = camera
        self.recordings = recordings
        self.getDayTimeline = getDayTimeline
        self.now = now
        self.instant = instant
        let present = now()
        span = TimeRange(start: present.addingTimeInterval(-Double(days) * 86_400), end: present)
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
        async let overlays: Void = loadOverlays(in: span)
        await load(window: window, seeking: .instant(instant))
        await overlays
    }

    /// Extends the span to the present and re-reads this camera's activity, without disturbing the
    /// playhead — history doesn't change, and the newly recorded stretch is what the track gains.
    public func refreshOverlays() async {
        let extended = TimeRange(start: span.start, end: now())
        await loadOverlays(in: extended)
        span = extended
    }

    /// Keeps the track current while the screen is visible. The owning `.task` cancels this loop
    /// when the view disappears.
    public func autoRefresh(every interval: Duration = .seconds(30)) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            await refreshOverlays()
        }
    }

    public func togglePlayPause() {
        setPlaying(!isPlaying)
    }

    public func select(_ speed: PlaybackSpeed) {
        self.speed = speed
        guard isPlaying else { return }
        player?.rate = speed.rate
    }

    public func select(_ zoom: TimelineZoom) {
        self.zoom = zoom
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

    /// Moves the playhead to a wall-clock instant, loading the hour holding it when that is not the
    /// hour already on screen. Every deliberate move — a settled drag, a marker jump, a day step,
    /// Live — funnels through here.
    ///
    /// The **readout keeps the instant asked for**, even inside a gap where the stream can only
    /// show the next recorded moment: reading the position back off the player would collapse the
    /// gap away and quietly report the wrong time.
    public func seek(to target: Date) async {
        let clamped = span.clamp(target)
        guard window.contains(clamped) else {
            await load(window: RecordingWindow.containing(clamped), seeking: .instant(clamped))
            return
        }
        // A seek is newer intent than any load still in flight — let it win.
        loadGeneration += 1
        apply(instant: clamped)
        guard timeline.playableDuration > 0 else { return }
        movePlayer(toPlayerTime: timeline.playerTime(at: clamped), exact: true)
    }

    /// Hands the playhead to a drag on the track — the transport would otherwise be driving the
    /// same instant the finger is.
    public func beginScrub() {
        setPlaying(false)
    }

    /// Follows the finger: the readout moves at once, and the stream follows it **only within the
    /// hour already loaded**, with a tolerant seek. Leaving that hour would mean a playlist fetch
    /// per drag frame, so a window swap waits for `endScrub()`.
    public func scrub(to target: Date) {
        let clamped = span.clamp(target)
        instant = clamped
        guard window.contains(clamped) else { return }
        hasFootage = timeline.hasFootage(at: clamped)
        guard timeline.playableDuration > 0 else { return }
        movePlayer(toPlayerTime: timeline.playerTime(at: clamped), exact: false)
    }

    /// Settles the drag on its final instant, swapping windows if it ran into another hour.
    public func endScrub() async {
        await seek(to: instant)
    }

    /// Jumps to the start of the next activity marker. Does nothing past the last one.
    public func jumpToNextMarker() async {
        guard let marker = MarkerNavigator.marker(after: instant, in: dayTimeline.markers) else { return }
        await seek(to: marker.start)
    }

    public func jumpToPreviousMarker() async {
        guard let marker = MarkerNavigator.marker(before: instant, in: dayTimeline.markers) else { return }
        await seek(to: marker.start)
    }

    /// Steps the playhead a whole day, clamped to the loaded history — the day stepper walks the
    /// span rather than falling off either end of it.
    public func stepDay(by days: Int) async {
        await seek(to: instant.addingTimeInterval(Double(days) * 86_400))
    }

    public func goLive() async {
        await seek(to: span.end)
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

    /// Best-effort: a failing activity endpoint leaves the track without overlays rather than
    /// failing the screen — the recording itself is what this screen is for, and it loads
    /// independently.
    private func loadOverlays(in range: TimeRange) async {
        guard let loaded = try? await getDayTimeline.execute(for: .camera(camera.name), in: range) else { return }
        dayTimeline = loaded
    }

    private func seek(toPlayerTime playerTime: TimeInterval) {
        let clamped = min(max(playerTime, 0), timeline.playableDuration)
        apply(instant: timeline.instant(atPlayerTime: clamped))
        movePlayer(toPlayerTime: clamped, exact: true)
    }

    /// Moves the stream alone, leaving the readout to the caller.
    ///
    /// An **exact** seek is what a settled position needs: a tolerant one lands on a keyframe
    /// seconds away, and the readout would then disagree with the instant that was asked for. A
    /// drag passes `exact: false` — it issues a seek per frame, and keyframe-accurate is both
    /// enough and far cheaper.
    private func movePlayer(toPlayerTime playerTime: TimeInterval, exact: Bool) {
        let tolerance = exact ? CMTime.zero : CMTime(seconds: 0.5, preferredTimescale: 600)
        player?.seek(
            to: CMTime(seconds: min(max(playerTime, 0), timeline.playableDuration), preferredTimescale: 600),
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
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
                // Only while running: paused, the playhead belongs to whoever positioned it, and
                // the observer's post-seek tick would otherwise collapse a gap-side instant onto
                // the footage the stream actually resumes at.
                guard let self, self.isPlaying, time.seconds.isFinite else { return }
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
