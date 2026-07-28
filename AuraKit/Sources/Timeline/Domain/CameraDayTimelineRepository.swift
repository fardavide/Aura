/// Supplies the day-timeline overlays (markers, motion, gaps) for a time window, over one camera
/// or all of them.
public protocol CameraDayTimelineRepository: Sendable {
    func dayTimeline(for scope: TimelineScope, in range: TimeRange) async throws(TimelineError) -> DayTimeline
}
