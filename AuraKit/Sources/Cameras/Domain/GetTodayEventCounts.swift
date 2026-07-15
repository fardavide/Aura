import Foundation

/// Tallies the events since the start of the current day into a total + per-label breakdown for the
/// grid's summary card. Best-effort at the call site: the card degrades gracefully if it throws.
public struct GetTodayEventCounts: Sendable {
    private let repository: any TodayEventsRepository
    private let now: @Sendable () -> Date

    public init(repository: any TodayEventsRepository, now: @escaping @Sendable () -> Date) {
        self.repository = repository
        self.now = now
    }

    public func execute() async throws(CamerasError) -> EventCount {
        let since = Calendar.current.startOfDay(for: now())
        let labels = try await repository.labels(since: since)
        return EventCount(total: labels.count, breakdown: breakdown(of: labels))
    }

    /// Groups labels into counts, ordered most-frequent first then alphabetically so ties are stable.
    private func breakdown(of labels: [String]) -> [EventCount.LabelCount] {
        Dictionary(labels.map { ($0, 1) }, uniquingKeysWith: +)
            .map { EventCount.LabelCount(label: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                lhs.count == rhs.count ? lhs.label < rhs.label : lhs.count > rhs.count
            }
    }
}
