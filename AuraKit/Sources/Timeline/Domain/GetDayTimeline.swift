/// Assembles the day timeline (markers, motion, gaps) for a time window, scoped to one camera or
/// all of them.
public struct GetDayTimeline: Sendable {
    private let repository: any CameraDayTimelineRepository

    public init(repository: any CameraDayTimelineRepository) {
        self.repository = repository
    }

    public func execute(for scope: TimelineScope, in range: TimeRange) async throws(TimelineError) -> DayTimeline {
        try await repository.dayTimeline(for: scope, in: range)
    }
}
