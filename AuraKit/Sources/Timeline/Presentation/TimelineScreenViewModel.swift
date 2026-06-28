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
    /// The continuous window the timeline scrolls over: `[now - days, now]`.
    public let span: TimeRange

    private let getCameras: GetCameras
    private let getDayTimeline: GetDayTimeline

    public init(getCameras: GetCameras, getDayTimeline: GetDayTimeline, now: Date, days: Int) {
        self.getCameras = getCameras
        self.getDayTimeline = getDayTimeline
        span = TimeRange(start: now.addingTimeInterval(-Double(days) * 86_400), end: now)
        clock = ScrubClock(instant: now)
    }

    public func load() async {
        state = .loading

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
