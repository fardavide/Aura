import Foundation

/// Supplies the day-timeline overlays (markers, motion, gaps) for one bounded window, over one
/// camera or all of them. `bucket` is the motion-strip bucket duration in seconds, chosen by the
/// caller from the full span (see `OverlayWindow.bucketDuration`) so every window of one span
/// comes back at the same resolution.
public protocol CameraDayTimelineRepository: Sendable {
    func dayTimeline(
        for scope: TimelineScope,
        in range: TimeRange,
        bucket: TimeInterval
    ) async throws(TimelineError) -> DayTimeline
}
