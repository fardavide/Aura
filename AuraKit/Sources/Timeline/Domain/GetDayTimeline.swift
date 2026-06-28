/// Assembles the day timeline (markers, motion, gaps) for a time window.
public struct GetDayTimeline: Sendable {
    private let repository: any CameraDayTimelineRepository

    public init(repository: any CameraDayTimelineRepository) {
        self.repository = repository
    }

    public func execute(in range: TimeRange) async throws(TimelineError) -> DayTimeline {
        try await repository.dayTimeline(in: range)
    }
}
