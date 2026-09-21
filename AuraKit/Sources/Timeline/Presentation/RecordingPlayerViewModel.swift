import AVFoundation
import Foundation
import Observation

import CamerasDomain
import CamerasEntities
import CommonPlayer
import ExportsDomain
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
        case live(AVPlayer)
        /// The hour holds no footage at all — the skips stay live so it can be left.
        case noFootage
        case failed
    }

    public let camera: Camera
    /// The Hour-zoom filmstrip's thumbnails — owned here so the strip survives zoom flips and
    /// re-layouts, handed to the layout beside `state`.
    public let filmstrip: RecordingFilmstripStore
    /// The same low-resolution preview path used by the main Timeline grid, shown while a drag
    /// owns the playhead so the hero follows without seeking the full-resolution recording.
    public let scrubPreview: PreviewTileViewModel
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
    public private(set) var isScrubbing = false

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
            isLive: followsLiveEdge,
            isPlayable: isPlayable,
            export: exportEditor,
            isPlayingSelection: isPlayingSelection
        )
    }

    /// The range editor, assembled from the mutable half (the selection and where the request has
    /// got to) and the screen's own live values. Keeping span, playhead, zoom and gaps out of
    /// stored state is what stops the editor drifting out of step with the track beneath it.
    private var exportEditor: ExportEditorState? {
        guard let exportSelection else { return nil }
        return ExportEditorState(
            selection: exportSelection,
            span: span,
            playhead: instant,
            zoom: zoom,
            gaps: dayTimeline.gaps,
            phase: exportPhase
        )
    }

    /// Whether there is anything to start or speed up. An hour holding no footage isn't playable,
    /// though the skips and the track stay live so it can be left.
    private var isPlayable: Bool {
        switch display {
        case .ready, .live: true
        case .loading, .noFootage, .failed: false
        }
    }

    /// The clip being cut, or `nil` outside export mode.
    private var exportSelection: ExportSelection?
    private var exportPhase: ExportEditorPhase = .editing
    /// Whether playback is fenced to the selection. Distinct from `isPlaying`, which stays the
    /// honest answer to whether the video is moving.
    public private(set) var isPlayingSelection = false
    @ObservationIgnored private var exportPollTask: Task<Void, Never>?

    private let recordings: GetCameraRecordings
    private let getDayTimeline: GetDayTimeline
    private let createExportUseCase: CreateExport
    private let getExport: GetExport
    private let liveSource: CameraStreamSource?
    private let now: @MainActor () -> Date
    /// The motion-strip resolution, pinned from the span at birth so every overlay window — and
    /// every refresh — comes back at the same bucket width.
    private let bucket: TimeInterval
    private var window: TimeRange
    private var timeline: RecordingTimeline
    /// The oldest instant overlays have been loaded back to. The window walk runs newest-first,
    /// so coverage is always the suffix `[overlaysLoadedBack, span.end]`; a walk an unreachable
    /// server cut short leaves this shy of the span start, and the next refresh resumes there.
    private var overlaysLoadedBack: Date
    /// How close to the live edge the playhead must be for a periodic refresh to fire — the same
    /// window the tab uses, so neither screen re-reads anything while history is browsed.
    private static let liveEdgeWindow: TimeInterval = 600
    /// How close to the span's end a deliberate move must land to count as "at the live edge".
    private static let liveEdgeTolerance: TimeInterval = 1
    /// How far inside the newest clip Live parks. Right on the boundary the half-open footage
    /// check would read "no footage" for the very frame being shown.
    private static let liveSettleBackoff: TimeInterval = 0.5
    /// Whether the playhead is parked at (or following) the newest recorded footage — what the
    /// Live chip and the hero badge read. Only a deliberate move away from the edge clears it;
    /// the player drifting a couple of seconds behind the wall clock must not read as history.
    private var followsLiveEdge: Bool
    /// Whether a track drag owns the playhead, and whether playback was running when it took it —
    /// the settle hands playback back, unless an explicit play/pause taken meanwhile wins.
    private var resumePlaybackOnSettle = false
    /// Stamps each grab of the track, so a settle that suspended on an hour fetch can tell a
    /// newer grab took the playhead while it was away — and yield to it.
    private var scrubGeneration = 0
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
        createExport: CreateExport,
        getExport: GetExport,
        filmstrip: RecordingFilmstripStore,
        scrubPreview: PreviewTileViewModel,
        liveSource: CameraStreamSource?,
        now: @escaping @MainActor () -> Date,
        startingAt instant: Date,
        days: Int
    ) {
        self.camera = camera
        self.filmstrip = filmstrip
        self.scrubPreview = scrubPreview
        self.recordings = recordings
        self.getDayTimeline = getDayTimeline
        createExportUseCase = createExport
        self.getExport = getExport
        self.liveSource = liveSource
        self.now = now
        self.instant = instant
        let present = now()
        let initialSpan = TimeRange(start: present.addingTimeInterval(-Double(days) * 86_400), end: present)
        span = initialSpan
        bucket = OverlayWindow.bucketDuration(for: initialSpan)
        overlaysLoadedBack = initialSpan.end
        followsLiveEdge = present.timeIntervalSince(instant) <= Self.liveEdgeTolerance
        let initial = RecordingWindow.containing(instant)
        window = initial
        timeline = RecordingTimeline(window: initial, segments: [])
    }

    isolated deinit {
        detachPlayer()
        exportPollTask?.cancel()
    }

    // MARK: - The export range editor

    /// Opens the editor on the track already on screen, seeded around the playhead, and snaps the
    /// axis to Minute — at Hour the seed is twelve points wide, so the editor would open onto a
    /// clip nobody could grab.
    public func beginExport() {
        guard let seed = ExportSelection.seeded(around: instant, within: span) else { return }
        exportSelection = seed
        exportPhase = .editing
        if !zoom.showsExportHandles || zoom == .hour { zoom = .minute }
    }

    /// Leaves with nothing created. Safe from any phase the user can still reach it from — and it
    /// is absent from the ones they cannot.
    public func cancelExport() {
        stopSelectionPlayback()
        exportPollTask?.cancel()
        exportPollTask = nil
        exportSelection = nil
        exportPhase = .editing
    }

    public func change(selection: ExportSelection) {
        // Editing a boundary while the selection is playing pauses it: the preview must not keep
        // running outside the range the user is now describing.
        stopSelectionPlayback()
        exportSelection = selection
        // Any move clears a rejection — the range the server refused no longer exists, so the
        // failure it reported no longer describes anything on screen.
        if case .failed = exportPhase { exportPhase = .editing }
    }

    public func resetSelectionToPlayhead() {
        guard let seed = ExportSelection.seeded(around: instant, within: span) else { return }
        change(selection: seed)
    }

    /// Seeks to the clip's start and plays, fenced by `fenceSelectionPlayback`.
    public func playSelection() async {
        guard let exportSelection else { return }
        if isPlayingSelection {
            stopSelectionPlayback()
            return
        }
        await seek(to: exportSelection.start)
        isPlayingSelection = true
        setPlaying(true)
    }

    public func createExport() async {
        guard let exportSelection else { return }
        stopSelectionPlayback()
        exportPhase = .creating
        do {
            let id = try await createExportUseCase.execute(
                camera: camera.name, from: exportSelection.start, to: exportSelection.end
            )
            exportPhase = .processing(id)
            followExport(id: id)
        } catch {
            exportPhase = .failed(error)
        }
    }

    /// Polls until the server says the cut has finished. `in_progress` is the server's own answer;
    /// readiness is never inferred from how long this has been running.
    private func followExport(id: ExportId) {
        exportPollTask?.cancel()
        exportPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                guard let export = try? await getExport.execute(id: id) else { continue }
                guard !Task.isCancelled else { return }
                if export.isReady {
                    exportPhase = .ready(export)
                    exportPollTask = nil
                    return
                }
            }
        }
    }

    /// The finished clip is dismissed and the panel returns to ordinary playback.
    public func finishExport() {
        cancelExport()
    }

    private func stopSelectionPlayback() {
        guard isPlayingSelection else { return }
        isPlayingSelection = false
        setPlaying(false)
    }

    /// Loads on first appearance only, so returning to the screen doesn't restart the recording.
    public func loadIfNeeded() async {
        guard case .loading = display else { return }
        isPlaying = true
        if followsLiveEdge, let liveSource {
            showLive(liveSource)
        }
        async let overlays = loadOverlays(in: span)
        async let preview: Void = scrubPreview.prepare(range: span, at: instant)
        await load(window: window, seeking: .instant(instant))
        _ = await overlays
        _ = await preview
    }

    /// Extends the span to the present and re-reads **only the stretch since the last read**,
    /// merged in place without disturbing the playhead — history doesn't change, and re-reading
    /// seven days of it every tick is what buried the server. A walk an unreachable server cut
    /// short earlier is resumed too; a refresh the server fails outright changes nothing and is
    /// retried on the next tick.
    public func refreshOverlays() async {
        let present = now()
        let wasFollowingLiveStream = switch display {
        case .live: followsLiveEdge
        case .loading, .ready, .noFootage, .failed: false
        }
        let delta = OverlayWindow.refresh(previousEnd: span.end, now: present, bucket: bucket)
        guard await loadOverlays(in: delta) > 0 else { return }
        if overlaysLoadedBack > span.start {
            await loadOverlays(in: TimeRange(start: span.start, end: overlaysLoadedBack))
        }
        span = TimeRange(start: span.start, end: present)
        if wasFollowingLiveStream {
            instant = present
        }
        await scrubPreview.followLiveEdge(to: span, at: instant)
    }

    /// Keeps the track current while the screen is visible — but only while the playhead sits
    /// near the live edge: browsing history re-reads nothing, because history doesn't change.
    /// The owning `.task` cancels this loop when the view disappears.
    public func autoRefresh(every interval: Duration = .seconds(30)) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            guard shouldRefreshNow else { continue }
            await refreshOverlays()
        }
    }

    /// Whether a periodic tick should fire: only when the playhead is at (or within ten minutes
    /// of) the live edge — the tab's gate, mirrored.
    var shouldRefreshNow: Bool {
        instant >= span.end.addingTimeInterval(-Self.liveEdgeWindow)
    }

    public func togglePlayPause() {
        // An explicit play or pause is newer intent than a drag's pending resume.
        resumePlaybackOnSettle = false
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
        let origin = instant
        let target = timeline.playerTime(at: instant) + seconds
        if target < 0 {
            let previous = RecordingWindow.containing(window.start.addingTimeInterval(-1))
            await load(window: previous, seeking: .latestFootage)
        } else if target > timeline.playableDuration {
            await loadFollowingWindow()
        } else {
            if case .live = display {
                followsLiveEdge = false
                await load(window: window, seeking: .instant(timeline.instant(atPlayerTime: target)))
            } else {
                seek(toPlayerTime: target)
            }
        }
        // Only a move that happened can demote the playhead to history — a forward skip with
        // nothing newer recorded is a no-op and must leave a live playhead live.
        guard instant != origin else { return }
        followsLiveEdge = span.end.timeIntervalSince(instant) <= Self.liveEdgeTolerance
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
        followsLiveEdge = span.end.timeIntervalSince(clamped) <= Self.liveEdgeTolerance
        if followsLiveEdge, let liveSource {
            instant = span.end
            speed = .oneX
            showLive(liveSource)
            return
        }
        if case .live = display {
            await load(window: RecordingWindow.containing(clamped), seeking: .instant(clamped))
            return
        }
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
    /// same instant the finger is. Playback the user was watching resumes when the drag settles;
    /// a chained grab (catching a fling mid-flight) keeps the original intent.
    public func beginScrub() {
        if !isScrubbing {
            isScrubbing = true
            resumePlaybackOnSettle = isPlaying
        }
        scrubGeneration += 1
        // Over loaded content a grab is also newer intent than any window load still in flight —
        // the drag owns the playhead, so a landing load must not yank it. (The very first load
        // stays: discarding it would strand the spinner.)
        switch display {
        case .ready, .live: loadGeneration += 1
        case .loading, .noFootage, .failed: break
        }
        setPlaying(false)
        scrubPreview.scrub(to: instant)
    }

    /// Follows the finger through the low-resolution preview material. The full-resolution stream
    /// is left alone until release; leaving its hour would otherwise fetch a playlist per frame.
    public func scrub(to target: Date) {
        let clamped = span.clamp(target)
        instant = clamped
        followsLiveEdge = span.end.timeIntervalSince(clamped) <= Self.liveEdgeTolerance
        scrubPreview.scrub(to: clamped)
        guard window.contains(clamped) else { return }
        hasFootage = timeline.hasFootage(at: clamped)
    }

    /// Settles the drag on its final instant, swapping windows if it ran into another hour, and
    /// hands playback back if the drag was what paused it. The settle can suspend on that swap's
    /// fetch — a newer grab taken meanwhile owns the playhead, so this one yields to it and the
    /// resume intent survives to the settle that is actually last.
    public func endScrub() async {
        let generation = scrubGeneration
        await seek(to: instant)
        guard generation == scrubGeneration else { return }
        isScrubbing = false
        guard resumePlaybackOnSettle else { return }
        resumePlaybackOnSettle = false
        if isPlayable { setPlaying(true) }
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
        // The wall clock runs ahead of the newest recorded frame — segments land seconds late —
        // so the edge itself usually has no footage. Park a hair inside the newest clip instead,
        // where the readout, the footage check and the shown frame all agree. Only over a loaded
        // window: after a failed live-hour fetch the timeline is still the old hour's, and
        // settling against it would teleport the readout to stale footage.
        guard case .ready = display, !hasFootage, timeline.playableDuration > Self.liveSettleBackoff else { return }
        let playerTime = timeline.playableDuration - Self.liveSettleBackoff
        apply(instant: timeline.instant(atPlayerTime: playerTime))
        movePlayer(toPlayerTime: playerTime, exact: true)
    }

    /// The stream played out. Continues into the next hour when there is one. Otherwise playback
    /// has caught up with the newest recorded footage — and the in-progress hour keeps growing
    /// behind the loaded copy, so it is refetched once: new footage carries playback on; none
    /// means the true live edge, and playback stops there until more is recorded.
    func advanceToNextWindow() async {
        if await loadFollowingWindow() { return }
        let playableBeforeRefetch = timeline.playableDuration
        // A user action taken while the refetch was in flight is newer intent — a superseded or
        // failed refetch must neither re-mark the playhead live nor pause what they resumed.
        guard await load(window: window, seeking: .instant(instant)) else { return }
        followsLiveEdge = true
        if timeline.playableDuration <= playableBeforeRefetch {
            setPlaying(false)
        }
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

    /// Answers whether the window was applied — `false` for a superseded or failed load, so a
    /// caller with follow-up state changes (the live-hour catch-up) knows to drop them too.
    @discardableResult
    private func load(window newWindow: TimeRange, seeking target: SeekTarget) async -> Bool {
        loadGeneration += 1
        let generation = loadGeneration
        let playback: RecordingPlayback
        do {
            playback = try await recordings.execute(for: camera.name, in: newWindow)
        } catch {
            // A torn-down fetch (the screen was left) is not a server failure — leave the state
            // for whatever replaces it rather than flashing an error on the way out.
            if Task.isCancelled || generation != loadGeneration { return false }
            if case .live = display, followsLiveEdge { return false }
            // Tear the old player down first: the error screen hides the transport, so a player
            // left running would keep streaming — and keep moving the playhead — unstoppably.
            detachPlayer()
            display = .failed
            isPlaying = false
            return false
        }
        guard generation == loadGeneration else { return false }
        // The live hour's catch-up refetch found nothing new: the player is already parked on the
        // newest frame, and rebuilding it would only blank the picture for the same frames.
        if newWindow == window, playback.timeline == timeline, case .ready = display { return true }
        window = newWindow
        timeline = playback.timeline
        if case .live = display, followsLiveEdge { return true }
        detachPlayer()

        guard timeline.playableDuration > 0 else {
            apply(instant: resolve(target))
            display = .noFootage
            isPlaying = false
            return true
        }
        let player = makeAuthedPlayer(url: playback.source.url, headers: playback.source.headers)
        attach(player, playing: newWindow)
        display = .ready(player)
        seek(toPlayerTime: timeline.playerTime(at: resolve(target)))
        // Read the intent now rather than capturing it at call time: a play/pause taken while the
        // fetch was in flight is the newer one and must not be reverted.
        setPlaying(isPlaying)
        return true
    }

    private func resolve(_ target: SeekTarget) -> Date {
        switch target {
        case .instant(let instant): instant
        case .latestFootage: timeline.instant(atPlayerTime: timeline.playableDuration)
        }
    }

    /// Streams this camera's overlay windows into the track, newest first, and answers how many
    /// landed — zero means the server failed the very first window. Best-effort throughout: a
    /// short walk leaves the track short rather than failing the screen — the recording itself is
    /// what this screen is for, and it loads independently.
    @discardableResult
    private func loadOverlays(in range: TimeRange) async -> Int {
        var applied = 0
        for await slice in getDayTimeline.execute(for: .camera(camera.name), in: range, bucket: bucket) {
            dayTimeline = dayTimeline.replacing(slice)
            overlaysLoadedBack = min(overlaysLoadedBack, slice.window.start)
            applied += 1
        }
        return applied
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
        fenceSelectionPlayback()
    }

    /// Selection playback stops at the trailing boundary and returns to the leading one — once,
    /// not on a loop. Looping is the obvious thing to want while trimming, but a loop with no
    /// visible loop control is a state the user can neither see nor deliberately stop.
    private func fenceSelectionPlayback() {
        guard isPlayingSelection, let exportSelection, instant >= exportSelection.end else { return }
        isPlayingSelection = false
        setPlaying(false)
        Task { await seek(to: exportSelection.start) }
    }

    /// Drives the rate rather than `play()`/`pause()` so resuming picks the chosen speed back up
    /// in one step instead of briefly running at 1×.
    private func setPlaying(_ playing: Bool) {
        isPlaying = playing
        player?.rate = playing ? speed.rate : 0
    }

    private func showLive(_ source: CameraStreamSource) {
        let shouldPlay = isPlaying
        detachPlayer()
        let player = makeAuthedPlayer(url: source.url, headers: source.headers)
        self.player = player
        display = .live(player)
        hasFootage = true
        player.rate = shouldPlay ? PlaybackSpeed.oneX.rate : 0
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
