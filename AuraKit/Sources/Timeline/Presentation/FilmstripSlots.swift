import Foundation

import TimelineDomain

/// The fixed grid the Hour-zoom filmstrip samples the footage on. Slots are epoch-aligned — like
/// `RecordingWindow` — so a slot keeps its identity (and its cached thumbnail) while the viewport
/// slides around it.
enum FilmstripSlots {
    /// How much footage one thumbnail stands for.
    static let duration: TimeInterval = 600

    /// The slot instants whose windows touch both the visible range and the span, oldest first —
    /// a slot wholly before the span's start or at/after its live edge holds no footage to sample.
    static func instants(visible: TimeRange, span: TimeRange) -> [Date] {
        var slots: [Date] = []
        var start = (visible.start.timeIntervalSince1970 / duration).rounded(.down) * duration
        while start < min(visible.end, span.end).timeIntervalSince1970 {
            if start + duration > span.start.timeIntervalSince1970 {
                slots.append(Date(timeIntervalSince1970: start))
            }
            start += duration
        }
        return slots
    }
}
