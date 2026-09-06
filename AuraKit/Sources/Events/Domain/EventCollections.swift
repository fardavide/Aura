import Foundation

/// Pure list logic over a loaded window of events — no state, no I/O.
extension [Event] {

    /// `.all` returns every event; `.label(l)` keeps events whose raw (case-sensitive) Frigate
    /// label matches. Display capitalisation is the view's concern, not this comparison's.
    public func matching(_ filter: EventFilter) -> [Event] {
        switch filter {
        case .all: self
        case .label(let label): self.filter { $0.label == label }
        }
    }

    /// `[.all]` followed by one `.label` per distinct label, ordered by count descending then
    /// label ascending. Empty input yields `[]` — no chip row at all, not a lone "All".
    public func labelFilters() -> [EventFilter] {
        guard !isEmpty else { return [] }
        var counts: [String: Int] = [:]
        for event in self {
            counts[event.label, default: 0] += 1
        }
        let ordered = counts.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
        }
        return [.all] + ordered.map { .label($0.key) }
    }

    /// Buckets on the hour-of-start, newest hour first, events inside a group newest first.
    public func groupedByHour(calendar: Calendar) -> [EventHourGroup] {
        var buckets: [Date: [Event]] = [:]
        for event in self {
            guard let hourStart = calendar.dateInterval(of: .hour, for: event.startTime)?.start else { continue }
            buckets[hourStart, default: []].append(event)
        }
        return buckets.keys.sorted(by: >).map { hourStart in
            EventHourGroup(
                hourStart: hourStart,
                events: buckets[hourStart, default: []].sorted { $0.startTime > $1.startTime }
            )
        }
    }

    /// The newest `.alert`, if any; otherwise the newest event; `nil` when empty. Same
    /// "alert over detection then recency" rule the Cameras summary card already uses.
    public func mostSignificant() -> Event? {
        let newestFirst = sorted { $0.startTime > $1.startTime }
        return newestFirst.first { $0.severity == .alert } ?? newestFirst.first
    }

    /// Keeps the events whose `startTime` falls on the calendar day of `instant`, then totals
    /// them and breaks them down by label, count descending then label ascending.
    public func summary(onDayOf instant: Date, calendar: Calendar) -> EventsSummary {
        guard let dayInterval = calendar.dateInterval(of: .day, for: instant) else {
            return EventsSummary(total: 0, breakdown: [])
        }
        let today = filter { dayInterval.contains($0.startTime) }
        var counts: [String: Int] = [:]
        for event in today {
            counts[event.label, default: 0] += 1
        }
        let breakdown = counts.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
        }.map { EventsSummary.LabelCount(label: $0.key, count: $0.value) }
        return EventsSummary(total: today.count, breakdown: breakdown)
    }
}
