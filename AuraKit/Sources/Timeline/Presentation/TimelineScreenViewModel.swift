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
    public private(set) var day: TimeRange

    private let getCameras: GetCameras
    private let getDayTimeline: GetDayTimeline
    private let calendar: Calendar

    public init(getCameras: GetCameras, getDayTimeline: GetDayTimeline, calendar: Calendar, now: Date) {
        self.getCameras = getCameras
        self.getDayTimeline = getDayTimeline
        self.calendar = calendar
        day = TimeRange.day(containing: now, in: calendar)
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
            let timeline = try await getDayTimeline.execute(in: day)
            state = .ready(cameras: cameras, timeline: timeline)
        } catch {
            state = .failed(error)
        }
    }

    public func selectDay(_ date: Date) async {
        day = TimeRange.day(containing: date, in: calendar)
        clock.scrub(to: day.clamp(clock.instant))
        await load()
    }

    public func scrub(to time: Date) {
        clock.scrub(to: day.clamp(time))
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
