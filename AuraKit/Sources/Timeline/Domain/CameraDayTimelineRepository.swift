/// Supplies the day-timeline overlays (markers, motion, gaps) for a time window.
public protocol CameraDayTimelineRepository: Sendable {
    func dayTimeline(in range: TimeRange) async throws(TimelineError) -> DayTimeline
}
