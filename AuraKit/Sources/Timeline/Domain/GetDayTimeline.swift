import Foundation

/// Assembles the day timeline (markers, motion, gaps) for a time window, scoped to one camera or
/// all of them — delivered as one slice per day-sized window rather than as one answer, because
/// a multi-day overlay query is what buries the server (see `OverlayWindow`).
public struct GetDayTimeline: Sendable {
    private let repository: any CameraDayTimelineRepository

    public init(repository: any CameraDayTimelineRepository) {
        self.repository = repository
    }

    /// Reads `range` one day-sized window at a time — sequentially, newest first, so the screen
    /// fills from the live edge backwards and the server is never asked for more than a day of
    /// rows at once, with room to answer everyone else between windows. The walk stops at the
    /// first window the repository fails on: an unreachable server should not be asked for the
    /// remaining days, and the slices already delivered stand on their own.
    public func execute(
        for scope: TimelineScope,
        in range: TimeRange,
        bucket: TimeInterval
    ) -> AsyncStream<DayTimelineSlice> {
        AsyncStream { continuation in
            let walk = Task {
                for window in OverlayWindow.windows(covering: range) {
                    guard
                        !Task.isCancelled,
                        let overlays = try? await repository.dayTimeline(for: scope, in: window, bucket: bucket)
                    else { break }
                    continuation.yield(DayTimelineSlice(window: window, overlays: overlays))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in walk.cancel() }
        }
    }
}
