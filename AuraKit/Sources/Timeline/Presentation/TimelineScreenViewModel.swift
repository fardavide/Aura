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

    private let getCameras: GetCameras
    private let getDayTimeline: GetDayTimeline
    private let now: @MainActor () -> Date

    /// How close to the present the playhead must be for an auto-refresh to fire. Generous so minor
    /// scroll drift never stops live updates, while genuine history browsing (hours/days back in a
    /// multi-day span) is excluded — historical footage doesn't change, so refreshing it is moot.
    private static let liveEdgeWindow: TimeInterval = 600

    public init(getCameras: GetCameras, getDayTimeline: GetDayTimeline, now: @escaping @MainActor () -> Date, days: Int) {
        self.getCameras = getCameras
        self.getDayTimeline = getDayTimeline
        self.now = now
        let start = now()
        span = TimeRange(start: start.addingTimeInterval(-Double(days) * 86_400), end: start)
        clock = ScrubClock(instant: start)
    }

    public func load() async {
        state = .loading
        span = TimeRange(start: span.start, end: now())

        let cameras: [Camera]
        do {
            cameras = try await getCameras.execute()
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
            state = .ready(cameras: cameras, timeline: timeline)
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

        let cameras: [Camera]
        switch state {
        case let .ready(loaded, _):
            cameras = loaded
        case .loading, .empty, .failed:
            do {
                cameras = try await getCameras.execute()
            } catch {
                return  // still unreachable — keep the current state, retry next tick
            }
            guard !cameras.isEmpty else { return }
        }

        do {
            let timeline = try await getDayTimeline.execute(in: extended)
            span = extended
            state = .ready(cameras: cameras, timeline: timeline)
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
