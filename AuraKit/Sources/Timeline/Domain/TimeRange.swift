import Foundation

/// A half-open time window `[start, end)` — the query window for timeline data and the span of
/// a preview clip.
public struct TimeRange: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public func contains(_ time: Date) -> Bool {
        time >= start && time < end
    }

    /// Keeps a time inside the window — used to keep the scrub handle within the day.
    public func clamp(_ time: Date) -> Date {
        min(max(time, start), end)
    }

    /// The calendar day containing `date`, as `[startOfDay, startOfNextDay)`.
    public static func day(containing date: Date, in calendar: Calendar) -> TimeRange {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return TimeRange(start: start, end: end)
    }
}
