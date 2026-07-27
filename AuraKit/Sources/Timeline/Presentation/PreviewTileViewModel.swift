import AVKit
import Foundation
import Observation
import SwiftUI

import CamerasDomain
import CommonPlayer
import TimelineDomain

/// One camera tile in the synced grid, in either of two modes.
///
/// **Parked** (the transport is not running) it shows the shared scrub instant off low-res material:
/// seeking a past-hour `preview.mp4`, or, in the live hour (no clip assembled yet), the nearest
/// still preview frame — coalesced through a `PreviewTileController`. That material is loaded for
/// the visible range and refreshed in place whenever the range's live edge grows.
///
/// **Playing** it streams the camera's own recording for the hour under the playhead, so the grid
/// runs at full resolution rather than through the scrub previews. The transport's clock stays
/// authoritative: the tile follows it, correcting its stream when the two drift apart and swapping
/// hours when the playhead leaves the loaded one.
@Observable
@MainActor
public final class PreviewTileViewModel {
    public enum Display {
        case loading
        case clip(AVPlayer)
        /// Full-resolution recorded footage — what the tile shows while the transport runs.
        case recording(AVPlayer)
        case frame(Image)
        case unavailable
        case failed
    }

    public let camera: Camera
    public private(set) var display: Display = .loading

    private let previews: GetCameraPreviews
    private let recordings: GetCameraRecordings
    private let imageLoader: any PreviewImageLoading
    private var clips: [PreviewClip] = []
    private var frames: [PreviewFrame] = []
    private var activeClip: PreviewClip?
    private var activeFrame: PreviewFrame?
    /// Whether the transport is running. Distinct from holding a `playback`: an hour with no footage
    /// leaves the tile on its scrub material while playback carries on around it.
    private var isPlaying = false
    /// The recording being played, when the transport is running. Nil whenever the tile is parked on
    /// its scrub material — including while playing an hour that turned out to hold no footage.
    private var playback: TilePlayback?
    /// The hour that came back with nothing playable, so the follow doesn't refetch it every tick.
    private var abandonedWindow: TimeRange?
    private var speed: PlaybackSpeed = .oneX
    @ObservationIgnored private var windowLoad: Task<Void, Never>?
    /// Stamps each window load so one that lands after a newer request — the playhead having moved
    /// on again, or playback having stopped — is dropped instead of yanking the tile backwards.
    private var loadGeneration = 0
    /// The newest externally requested instant — what a (re)load re-applies when it lands, so a
    /// scrub that arrived while the fetch was in flight wins over the instant captured at its start.
    private var lastRequestedInstant: Date?
    @ObservationIgnored private lazy var controller = PreviewTileController(scrubber: self, tolerance: 0.5)

    /// How far the stream may drift from the transport's clock before it is seeked back. The clock
    /// ticks many times a second while the stream runs on its own; correcting every small
    /// disagreement would seek continuously and never let the picture settle.
    private static let driftTolerance: TimeInterval = 1

    public init(
        camera: Camera,
        previews: GetCameraPreviews,
        recordings: GetCameraRecordings,
        imageLoader: any PreviewImageLoading
    ) {
        self.camera = camera
        self.previews = previews
        self.recordings = recordings
        self.imageLoader = imageLoader
    }

    /// The first load for the tile's window. The view drives this off the **fixed span start**, so
    /// extending the live edge (which moves only the end) can no longer cancel an in-flight first
    /// load and strand the tile on its spinner. Loads from scratch while on the spinner or after a
    /// failure; a re-appearance over already-loaded material refreshes it in place.
    public func prepare(range: TimeRange, at instant: Date) async {
        switch display {
        case .loading, .failed:
            await loadFromScratch(range: range, at: instant)
        // `.recording` refreshes its scrub material too, so leaving playback lands on current
        // previews — `refreshInPlace` leaves the running stream alone.
        case .clip, .recording, .frame, .unavailable:
            await refreshInPlace(range: range, at: instant)
        }
    }

    /// Follows the growing live edge — the view drives this off the span **end**, a trigger separate
    /// from the first load, so newly recorded footage reaches the tile without an extension ever
    /// tearing down (cancelling) an in-flight first load. While the first load is still on the
    /// spinner this does nothing, so it can neither race nor duplicate it; once material is present
    /// (or the load has failed) it defers to `prepare` to refresh in place or retry from scratch.
    public func followLiveEdge(to range: TimeRange, at instant: Date) async {
        if case .loading = display { return }
        await prepare(range: range, at: instant)
    }

    public func scrub(to time: Date) {
        lastRequestedInstant = time
        guard isPlaying else {
            controller.scrub(to: time)
            return
        }
        follow(to: time)
    }

    /// Enters full-resolution playback at `instant`, streaming the hour that holds it.
    public func beginPlayback(at instant: Date, speed: PlaybackSpeed) async {
        isPlaying = true
        self.speed = speed
        lastRequestedInstant = instant
        abandonedWindow = nil
        await load(window: RecordingWindow.containing(instant), at: instant)
    }

    /// Leaves playback and puts the tile back on its scrub material at the instant it stopped.
    /// Does nothing when the tile was never playing — the view drives this off the transport's
    /// state, which is "not playing" on a first appearance too, and a tile still on its spinner
    /// must not be pushed onto the (empty) scrub material before its first load has even run.
    public func endPlayback(at instant: Date) {
        guard isPlaying else { return }
        isPlaying = false
        loadGeneration += 1
        windowLoad?.cancel()
        windowLoad = nil
        fallBackToPreview(at: instant)
    }

    public func select(_ speed: PlaybackSpeed) {
        self.speed = speed
        playback?.player.rate = speed.rate
    }

    private func loadFromScratch(range: TimeRange, at instant: Date) async {
        let loadedClips: [PreviewClip]
        do {
            loadedClips = try await previews.clips(for: camera.name, in: range)
        } catch {
            // A torn-down fetch (the view re-keyed, or the tile left the screen) is not a server
            // failure — leave the display for the replacement load instead of flashing an error.
            if Task.isCancelled { return }
            display = .failed
            return
        }
        clips = loadedClips
        // Frames are best-effort: a failure degrades the live hour to the frozen-clip fallback,
        // never to a full-tile error (the clips already loaded).
        frames = (try? await previews.frames(for: camera.name, in: range)) ?? []
        activeClip = nil
        activeFrame = nil
        // A tile that appeared while the transport was already running has a stream on screen by
        // now; the material just loaded is for when playback stops, not to be shown over it.
        guard playback == nil else { return }
        controller.scrub(to: lastRequestedInstant ?? instant)
    }

    /// Refetches the range's material without resetting the active clip/frame: an unchanged clip
    /// keeps its player (value-equal on re-fetch, so `seek` won't rebuild it) and an unchanged
    /// frame skips its reload. A transient fetch failure keeps the last good material.
    private func refreshInPlace(range: TimeRange, at instant: Date) async {
        guard let refreshedClips = try? await previews.clips(for: camera.name, in: range) else { return }
        clips = refreshedClips
        frames = (try? await previews.frames(for: camera.name, in: range)) ?? frames
        // Leave a running stream alone. A *playing* tile with nothing streaming (an hour that held
        // no footage) is on its previews, so it still follows the refresh.
        guard playback == nil else { return }
        controller.scrub(to: lastRequestedInstant ?? instant)
    }

    /// Keeps the stream under the transport's clock: correcting it where they have drifted apart,
    /// and swapping hours where the playhead has left the one being streamed.
    private func follow(to time: Date) {
        if let playback, playback.window.contains(time) {
            let drift = playback.player.currentTime().seconds - playback.timeline.playerTime(at: time)
            guard abs(drift) > Self.driftTolerance else { return }
            seek(playback, toPlayerTime: playback.timeline.playerTime(at: time))
            return
        }
        // Nothing is streaming for this instant — the hour held no footage, its read failed, or the
        // playhead has moved on. Keep the scrub material current so the tile never goes blank
        // mid-playback, and try the hour it is in now.
        if playback == nil {
            controller.scrub(to: time)
        }
        loadWindow(containing: time)
    }

    /// Fetches the hour holding `time`, unless one is already in flight or that hour has already
    /// come back with nothing to play — playback ticks many times a second, so an ungated retry
    /// would refetch the same empty hour continuously.
    private func loadWindow(containing time: Date) {
        let window = RecordingWindow.containing(time)
        guard window != abandonedWindow, windowLoad == nil else { return }
        windowLoad = Task { [weak self] in
            await self?.load(window: window, at: time)
            self?.windowLoad = nil
        }
    }

    private func load(window: TimeRange, at instant: Date) async {
        loadGeneration += 1
        let generation = loadGeneration
        let recording: RecordingPlayback
        do {
            recording = try await recordings.execute(for: camera.name, in: window)
        } catch {
            // A torn-down fetch (playback stopped, or the tile left the screen) is not a server
            // failure — leave the display for whatever replaces it.
            if Task.isCancelled || generation != loadGeneration { return }
            abandonedWindow = window
            fallBackToPreview(at: lastRequestedInstant ?? instant)
            return
        }
        guard generation == loadGeneration else { return }
        // Read the target now rather than capturing it at call time: the playhead kept moving while
        // the fetch was in flight, and where it is now is where the stream must open.
        let target = lastRequestedInstant ?? instant
        guard recording.timeline.playableDuration > 0 else {
            // An hour with nothing recorded isn't a failure — the transport plays on, and the tile
            // shows its scrub material until the playhead reaches an hour that has footage.
            abandonedWindow = window
            fallBackToPreview(at: target)
            return
        }
        abandonedWindow = nil
        detachPlayback()
        let player = makeAuthedPlayer(url: recording.source.url, headers: recording.source.headers)
        let started = TilePlayback(window: window, timeline: recording.timeline, player: player)
        playback = started
        display = .recording(player)
        seek(started, toPlayerTime: recording.timeline.playerTime(at: target))
        player.rate = speed.rate
    }

    private func seek(_ playback: TilePlayback, toPlayerTime playerTime: TimeInterval) {
        // Exact: a tolerant seek lands on a keyframe seconds away, which is exactly the drift this
        // is here to remove — the next tick would only seek again.
        playback.player.seek(
            to: CMTime(seconds: playerTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    /// Tears the stream down and puts the tile back on its scrub material at `instant`.
    private func fallBackToPreview(at instant: Date) {
        detachPlayback()
        // The preview player was released when playback took over the display, so let the scrub
        // path rebuild it rather than seek one that is no longer on screen.
        activeClip = nil
        activeFrame = nil
        controller.scrub(to: instant)
    }

    private func detachPlayback() {
        playback?.player.rate = 0
        playback = nil
    }
}

/// The recording a tile is currently streaming: the hour it covers, the mapping from the transport's
/// wall clock onto that stream's own clock, and the player running it.
private struct TilePlayback {
    let window: TimeRange
    let timeline: RecordingTimeline
    let player: AVPlayer
}

extension PreviewTileViewModel: PreviewScrubber {
    func scrub(to time: Date, completion: @escaping @MainActor () -> Void) {
        // Past hours: a low-res mp4 covers this instant — seek it locally (smooth, no network).
        if let clip = clips.first(where: { $0.contains(time) }) {
            seek(clip, to: time, completion: completion)
            return
        }
        // Live hour: Frigate has no mp4 for the in-progress hour yet, so show the nearest still frame
        // — this is what keeps the tile current at the live edge instead of freezing an hour back.
        if let frame = frames.mostRecent(atOrBefore: time) {
            show(frame, completion: completion)
            return
        }
        // At/after the live edge with no frame available — fall back to the latest clip's last frame.
        if let latest = clips.max(by: { $0.range.start < $1.range.start }), time >= latest.range.end {
            seek(latest, to: time, completion: completion)
            return
        }
        activeClip = nil
        activeFrame = nil
        display = .unavailable
        completion()
    }

    private func seek(_ clip: PreviewClip, to time: Date, completion: @escaping @MainActor () -> Void) {
        activeFrame = nil
        if clip != activeClip {
            activeClip = clip
            let source = previews.clipSource(clip)
            display = .clip(makeAuthedPlayer(url: source.url, headers: source.headers))
        }
        guard case let .clip(player) = display else {
            completion()
            return
        }
        // Clamp into the clip so the live edge (no finished clip yet) shows the latest footage.
        let target = Swift.min(Swift.max(time, clip.range.start), clip.range.end)
        player.seek(
            to: CMTime(seconds: target.timeIntervalSince(clip.range.start), preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600)
        ) { _ in
            Task { @MainActor in completion() }
        }
    }

    private func show(_ frame: PreviewFrame, completion: @escaping @MainActor () -> Void) {
        activeClip = nil
        // Already showing this frame — skip the reload (webp is immutable, but avoid the churn).
        if frame == activeFrame, case .frame = display {
            completion()
            return
        }
        activeFrame = frame
        Task { @MainActor in
            if let image = await imageLoader.frameImage(frame).flatMap(platformImage(from:)) {
                display = .frame(image)
            } else if case .loading = display {
                // A first load whose frame image failed must not sit on `.loading` — that reads as
                // "first load still in flight", which makes `followLiveEdge` skip the tile, so the
                // live-edge refresh would never retry it (it would spin forever whenever the playhead
                // is parked behind the edge). Resolve to the placeholder instead: the tile leaves the
                // spinner and the next extension re-fetches it through `refreshInPlace`.
                display = .unavailable
            }
            // A loaded tile keeps its last good frame on a failure (don't flash) — a later scrub retries.
            completion()
        }
    }
}
