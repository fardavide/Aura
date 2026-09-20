import Foundation

public extension [Export] {

    /// Groups into calendar days, newest day first and newest clip first inside each — the order the
    /// list renders. `calendar` is injected rather than read from `.current` so the boundary is the
    /// caller's, and a test can pin a time zone.
    func groupedByDay(calendar: Calendar) -> [ExportDayGroup] {
        Dictionary(grouping: self) { calendar.startOfDay(for: $0.createdAt) }
            .map { day, exports in
                ExportDayGroup(dayStart: day, exports: exports.sorted { $0.createdAt > $1.createdAt })
            }
            .sorted { $0.dayStart > $1.dayStart }
    }

    /// What the header says under the title. Counts distinct cameras, not rows, because the question
    /// it answers is "is anything missing", not "how big is the list".
    var summary: ExportsSummary {
        ExportsSummary(clipCount: count, cameraCount: Set(map(\.camera)).count)
    }
}
