import Foundation

import TimelineDomain

/// One calendar day of the timeline reduced to what the 24-hour overview bar draws: an hourly
/// motion rollup, the day's alerts, and the stretches with no footage.
///
/// Derived from the `DayTimeline` already loaded rather than from Frigate's own hourly summary —
/// the buckets are in hand, and a second round trip per day step would be visible.
struct DayOverview: Equatable {
    static let hoursInDay = 24

    let day: TimeRange
    /// Mean motion intensity (0–100) per hour of the day, always `hoursInDay` long. Mean, not peak:
    /// the bar answers "how busy was this hour", which a peak would saturate on a single burst.
    let hourlyMotion: [Int]
    /// Where the day's alerts start — the red ticks along the top of the bar.
    let alerts: [Date]
    /// No-footage stretches, clipped to the day so a gap crossing midnight draws on both days.
    let gaps: [TimeRange]

    static func rolledUp(from timeline: DayTimeline, day: TimeRange, calendar: Calendar) -> DayOverview {
        var totals = [Int](repeating: 0, count: hoursInDay)
        var counts = [Int](repeating: 0, count: hoursInDay)
        for bucket in timeline.motion where day.contains(bucket.time) {
            let hour = calendar.component(.hour, from: bucket.time)
            guard hour < hoursInDay else { continue }
            totals[hour] += bucket.intensity
            counts[hour] += 1
        }

        return DayOverview(
            day: day,
            hourlyMotion: zip(totals, counts).map { total, count in
                count == 0 ? 0 : Int((Double(total) / Double(count)).rounded())
            },
            alerts: timeline.markers
                .filter { $0.severity == .alert && day.contains($0.start) }
                .map(\.start),
            gaps: timeline.gaps.compactMap { gap in
                let start = Swift.max(gap.range.start, day.start)
                let end = Swift.min(gap.range.end, day.end)
                return start < end ? TimeRange(start: start, end: end) : nil
            }
        )
    }
}
