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
    /// The continuous window the timeline scrolls over: `[start, now]`. The start is fixed for the
    /// life of the screen; a refresh only extends the end to the present so newly recorded footage
    /// appears at the live edge without reloading the tiles (which key off `span.start`).
    public private(set) var span: TimeRange

    private let observeCameras: ObserveCameras
    private let getDayTimeline: GetDayTimeline
    private let now: @MainActor () -> Date
    private var observation: Task<Void, Never>?
    /// The freshest stream emission — read at ready-time so an order change landing while
    /// the timeline fetch is in flight is not lost.
    private var latestCameras: [Camera] = []

    /// How close to the present the playhead must be for an auto-refresh to fire. Generous so minor
    /// scroll drift never stops live updates, while genuine history browsing (hours/days back in a
    /// multi-day span) is excluded — historical footage doesn't change, so refreshing it is moot.
    private static let liveEdgeWindow: TimeInterval = 600

    public init(observeCameras: ObserveCameras, getDayTimeline: GetDayTimeline, now: @escaping @MainActor () -> Date, days: Int) {
        self.observeCameras = observeCameras
        self.getDayTimeline = getDayTimeline
        self.now = now
        let start = now()
        span = TimeRange(start: start.addingTimeInterval(-Double(days) * 86_400), end: start)
        clock = ScrubClock(instant: start)
    }

    isolated deinit {
        observation?.cancel()
    }

    public func load() async {
        state = .loading
        span = TimeRange(start: span.start, end: now())

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

        do {
            let timeline = try await getDayTimeline.execute(in: span)
            state = .ready(cameras: latestCameras, timeline: timeline)
        } catch {
            state = .failed(error)
        }
    }

    /// Loads on first appearance only. A re-appearance (e.g. returning to the tab) keeps the
    /// already-loaded content instead of flashing the full-screen spinner and refetching.
    public func loadIfNeeded() async {
        guard case .loading = state else { return }
        await load()
    }

    /// Keeps the timeline current while the screen is visible: re-fetches every `interval`, only
    /// when it won't disturb the user (see `shouldRefreshNow`). The owning `.task` cancels this loop
    /// when the view disappears.
    public func autoRefresh(every interval: Duration = .seconds(30)) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            if Task.isCancelled { return }
            guard shouldRefreshNow else { continue }
            await refresh()
        }
    }

    /// Re-fetches the timeline against a span extended to the present, without flashing the
    /// full-screen spinner. Reuses the already-loaded cameras when present; otherwise (initial or
    /// recovered-from-failure) it loads them too. A transient failure keeps the last good content.
    public func refresh() async {
        let extended = TimeRange(start: span.start, end: now())

        switch state {
        case .ready:
            break
        case .loading, .empty, .failed:
            let cameras: [Camera]
            do {
                cameras = try await startObservingCameras()
            } catch {
                return  // still unreachable — keep the current state, retry next tick
            }
            guard !cameras.isEmpty else { return }
        }

        do {
            let timeline = try await getDayTimeline.execute(in: extended)
            span = extended
            // latestCameras, not a pre-fetch snapshot: an order change that landed while
            // the timeline fetch was in flight must survive this write.
            state = .ready(cameras: latestCameras, timeline: timeline)
        } catch {
            return  // transient blip — keep the last good timeline rather than show an error
        }
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
