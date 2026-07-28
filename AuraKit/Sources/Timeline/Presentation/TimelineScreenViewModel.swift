import Foundation
import Observation

import CamerasDomain
import TimelineDomain

@Observable
@MainActor
public final class TimelineScreenViewModel {
    public enum State: Equatable {
        case loading
        case ready(cameras: [Camera], timeline: DayTimeline)
        case empty
        case failed(TimelineError)
    }

    public private(set) var state: State = .loading
    public let clock: ScrubClock
    /// Play/pause and the speed ladder, driving the same clock the scrubber writes. Kept fed with
    /// the loaded gaps and span so playback steps over missing footage and stops at the live edge.
    public let transport: TimelineTransport
    /// The continuous window the timeline scrolls over: `[start, now]`. The start is fixed for the
    /// life of the screen; a refresh only extends the end to the present, and each extension has
    /// the tiles refresh their preview material in place so newly recorded footage appears at the
    /// live edge.
    public private(set) var span: TimeRange

    private let observeCameras: ObserveCameras
    private let getDayTimeline: GetDayTimeline
    private let now: @MainActor () -> Date
    /// The motion-strip resolution, pinned from the span at birth so every overlay window — and
    /// every refresh — comes back at the same bucket width.
    private let bucket: TimeInterval
    private var observation: Task<Void, Never>?
    /// The freshest stream emission — read at ready-time so an order change landing while
    /// the timeline fetch is in flight is not lost.
    private var latestCameras: [Camera] = []
    /// The oldest instant overlays have been loaded back to. The window walk runs newest-first,
    /// so coverage is always the suffix `[overlaysLoadedBack, span.end]`; a walk an unreachable
    /// server cut short leaves this shy of the span start, and the next refresh resumes there.
    private var overlaysLoadedBack: Date

    /// How close to the present the playhead must be for an auto-refresh to fire. Generous so minor
    /// scroll drift never stops live updates, while genuine history browsing (hours/days back in a
    /// multi-day span) is excluded — historical footage doesn't change, so refreshing it is moot.
    private static let liveEdgeWindow: TimeInterval = 600

    public init(observeCameras: ObserveCameras, getDayTimeline: GetDayTimeline, now: @escaping @MainActor () -> Date, days: Int) {
        self.observeCameras = observeCameras
        self.getDayTimeline = getDayTimeline
        self.now = now
        let start = now()
        let initialSpan = TimeRange(start: start.addingTimeInterval(-Double(days) * 86_400), end: start)
        let initialClock = ScrubClock(instant: start)
        span = initialSpan
        clock = initialClock
        transport = TimelineTransport(clock: initialClock, now: now, span: initialSpan)
        bucket = OverlayWindow.bucketDuration(for: initialSpan)
        overlaysLoadedBack = initialSpan.end
    }

    isolated deinit {
        observation?.cancel()
    }

    public func load() async {
        state = .loading
        span = TimeRange(start: span.start, end: now())
        overlaysLoadedBack = span.end

        let cameras: [Camera]
        do {
            cameras = try await startObservingCameras()
        } catch {
            state = .failed(error.asTimelineError)
            return
        }

        guard !cameras.isEmpty else {
            state = .empty
            return
        }

        // Paint the grid at once over empty overlays — the timeline windows stream in behind it,
        // and a server with only its activity endpoints down still shows its cameras.
        state = .ready(cameras: latestCameras, timeline: DayTimeline(markers: [], motion: [], gaps: []))
        transport.update(gaps: [], span: span)
        await loadOverlays(in: span)
    }

    /// Loads on first appearance only. A re-appearance (e.g. returning to the tab) keeps the
    /// already-loaded content instead of flashing the full-screen spinner and refetching.
    public func loadIfNeeded() async {
        guard case .loading = state else { return }
        await load()
    }

    /// Keeps the timeline current while the screen is visible: checks immediately on entry — a
    /// re-entered screen catches up right away instead of showing a stale live edge for a full
    /// tick — then re-checks every `interval`, only when it won't disturb the user (see
    /// `shouldRefreshNow`). The owning `.task` cancels this loop when the view disappears.
    public func autoRefresh(every interval: Duration = .seconds(30)) async {
        while !Task.isCancelled {
            if shouldRefreshNow {
                await refresh()
            }
            try? await Task.sleep(for: interval)
        }
    }

    /// Re-fetches the timeline against a span extended to the present, without flashing the
    /// full-screen spinner. Concurrent calls — the periodic tick racing the scene-activation
    /// catch-up on the same appearance — coalesce into one fetch; both callers await it.
    public func refresh() async {
        if let inFlight = refreshTask {
            await inFlight.value
            return
        }
        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private var refreshTask: Task<Void, Never>?

    /// How far the playhead may sit behind the live edge and still count as "parked at it" for the
    /// post-refresh follow. Sub-second drift only (load sets the span end moments after the clock):
    /// anything the user deliberately positioned — even seconds back — must stay put, so this is
    /// far tighter than the auto-refresh gate's `liveEdgeWindow`.
    private static let playheadFollowTolerance: TimeInterval = 1

    /// Reuses the already-loaded content when present — re-reading **only the stretch since the
    /// last read**, because history is settled and re-reading seven days of it every tick is what
    /// buried the server. From a failure it reloads cameras and the whole span. A transient
    /// failure keeps the last good content.
    private func performRefresh() async {
        let extended = TimeRange(start: span.start, end: now())
        // The old live edge, before the span jumps — the reference for the playhead follow below.
        let previousEnd = span.end

        switch state {
        case .ready:
            let delta = OverlayWindow.refresh(previousEnd: previousEnd, now: extended.end, bucket: bucket)
            guard await loadOverlays(in: delta) > 0 else {
                return  // still unreachable — keep the current span, retry next tick
            }
        case .loading, .empty, .failed:
            do {
                let cameras = try await startObservingCameras()
                guard !cameras.isEmpty else { return }
            } catch {
                return  // still unreachable — keep the current state, retry next tick
            }
            state = .ready(cameras: latestCameras, timeline: DayTimeline(markers: [], motion: [], gaps: []))
            overlaysLoadedBack = extended.end
            guard await loadOverlays(in: extended) > 0 else { return }
        }

        // A walk the server cut short earlier resumes here, one day-sized window at a time.
        if overlaysLoadedBack > span.start {
            await loadOverlays(in: TimeRange(start: span.start, end: overlaysLoadedBack))
        }

        span = extended
        if case let .ready(_, timeline) = state {
            // The live edge just moved: playback that had stopped there now has somewhere to go.
            transport.update(gaps: timeline.gaps, span: extended)
        }
        // Follow only a playhead parked at the *old* live edge, judged entirely at landing —
        // a drag that began, or even settled elsewhere, while the fetch was in flight is never
        // yanked. This keeps the readout and tiles tracking the present across a long
        // suspension (where the gap far exceeds the refresh gate's window).
        if !clock.isScrubbing, previousEnd.timeIntervalSince(clock.instant) <= Self.playheadFollowTolerance {
            clock.scrub(to: extended.end)
        }
    }

    /// Streams overlay windows into the ready state, newest first, and answers how many landed —
    /// zero means the server failed the very first window. An order change landing mid-walk is
    /// safe: each slice merges into the state current at that moment, cameras included.
    @discardableResult
    private func loadOverlays(in range: TimeRange) async -> Int {
        var applied = 0
        for await slice in getDayTimeline.execute(for: .allCameras, in: range, bucket: bucket) {
            guard case let .ready(cameras, timeline) = state else { break }
            let merged = timeline.replacing(slice)
            state = .ready(cameras: cameras, timeline: merged)
            transport.update(gaps: merged.gaps, span: span)
            overlaysLoadedBack = min(overlaysLoadedBack, slice.window.start)
            applied += 1
        }
        return applied
    }

    /// Whether an auto-refresh tick should fire now. Never interrupts an active scrub; over loaded
    /// content only when parked at the live edge; over a failed screen it keeps trying to recover.
    var shouldRefreshNow: Bool {
        if clock.isScrubbing { return false }
        switch state {
        case .ready: return isViewingLiveEdge
        case .failed: return true
        case .loading, .empty: return false
        }
    }

    var isViewingLiveEdge: Bool {
        clock.instant >= span.end.addingTimeInterval(-Self.liveEdgeWindow)
    }

    public func scrub(to time: Date) {
        clock.scrub(to: span.clamp(time))
    }

    /// Restarts the camera observation and returns its first emission. The observation keeps
    /// running for the screen's life: an order change re-sorts the ready grid in place.
    private func startObservingCameras() async throws(CamerasError) -> [Camera] {
        observation?.cancel()
        let stream = try await observeCameras.execute()
        // A racing caller may have assigned a fresh observation while we were suspended
        // above — cancel it too, or it would leak and keep writing state forever.
        observation?.cancel()
        return await withCheckedContinuation { continuation in
            observation = Task { [weak self] in
                var firstEmission: CheckedContinuation<[Camera], Never>? = continuation
                for await cameras in stream {
                    self?.latestCameras = cameras
                    if let first = firstEmission {
                        first.resume(returning: cameras)
                        firstEmission = nil
                        continue
                    }
                    if case let .ready(_, timeline) = self?.state {
                        self?.state = .ready(cameras: cameras, timeline: timeline)
                    }
                }
                firstEmission?.resume(returning: [])
            }
        }
    }
}

private extension CamerasError {
    var asTimelineError: TimelineError {
        switch self {
        case .unreachable: .unreachable
        case .notAuthorized: .notAuthorized
        case .serverUnavailable: .serverUnavailable
        case .invalidData: .invalidData
        case .unknown: .unknown
        }
    }
}
