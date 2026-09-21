import Foundation

/// The clip a user is cutting out of one camera's recordings: two instants on the timeline, and
/// the rules that keep them a request the server will accept.
///
/// **Every bound is a whole second, and the truncation happens here** rather than on the way out.
/// Frigate 0.17.2 converts export bounds to integers internally, so a selection carrying fractions
/// would promise a precision the server discards — and the readout would disagree with the file.
/// Quantising in the initializer makes that an invariant of the type instead of a step someone has
/// to remember.
///
/// The bounds move independently (`movingStart`/`movingEnd`) or together (`movingWholeRange`), and
/// every move is clamped to the available history. Gaps are deliberately **not** bounds: a
/// selection may span or begin inside one, because the server exports the footage that exists and
/// the result is simply shorter. The only invalid selection is one holding no recorded second at
/// all, which is `hasRecording(gaps:)`.
public struct ExportSelection: Equatable, Sendable {
    public let start: Date
    public let end: Date

    /// The shortest clip the server is asked for. A boundary stops here rather than crossing.
    public static let minimumDuration: TimeInterval = 1
    /// How far either side of the playhead a fresh selection reaches.
    public static let seedLead: TimeInterval = 30
    public static let seedTrail: TimeInterval = 60

    public init(start: Date, end: Date) {
        self.start = start.flooredToSecond
        self.end = end.flooredToSecond
    }

    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }

    /// The selection a fresh export mode opens with: `playhead − 30s … playhead + 60s`, clamped to
    /// the history actually available. Clamped rather than shifted — near the live edge the clip is
    /// shorter, which is the truth, instead of silently reaching further back than the user asked.
    ///
    /// `nil` when the camera holds under a second of history, which is the one case where there is
    /// nothing to cut and the entry point has to say so.
    public static func seeded(around playhead: Date, within span: TimeRange) -> ExportSelection? {
        let earliest = span.start.ceilingToSecond
        let latest = span.end.flooredToSecond
        guard latest.timeIntervalSince(earliest) >= minimumDuration else { return nil }

        let anchor = playhead.flooredToSecond
        var start = max(earliest, anchor.addingTimeInterval(-seedLead))
        var end = min(latest, anchor.addingTimeInterval(seedTrail))
        // A playhead parked within a second of the live edge would otherwise seed an empty clip.
        if end.timeIntervalSince(start) < minimumDuration {
            end = min(latest, start.addingTimeInterval(minimumDuration))
            start = max(earliest, end.addingTimeInterval(-minimumDuration))
        }
        return ExportSelection(start: start, end: end)
    }

    /// Moves the leading boundary. It stops a second short of the trailing one rather than crossing
    /// it, and never swaps roles — a handle the user grabbed as "start" stays the start.
    public func movingStart(to instant: Date, within span: TimeRange) -> ExportSelection {
        let earliest = span.start.ceilingToSecond
        let target = instant.flooredToSecond
        let bounded = min(max(target, earliest), end.addingTimeInterval(-Self.minimumDuration))
        return ExportSelection(start: max(bounded, earliest), end: end)
    }

    /// The same, trailing.
    public func movingEnd(to instant: Date, within span: TimeRange) -> ExportSelection {
        let latest = span.end.flooredToSecond
        let target = instant.flooredToSecond
        let bounded = max(min(target, latest), start.addingTimeInterval(Self.minimumDuration))
        return ExportSelection(start: start, end: min(bounded, latest))
    }

    /// Slides the whole clip without resizing it. At either bound the range stops as a unit — it
    /// never compresses, because the duration is the thing the user is holding constant.
    public func movingWholeRange(toStart instant: Date, within span: TimeRange) -> ExportSelection {
        let earliest = span.start.ceilingToSecond
        let latest = span.end.flooredToSecond
        let held = duration
        let lastStart = latest.addingTimeInterval(-held)
        let target = min(instant.flooredToSecond, lastStart)
        let start = max(target, earliest)
        return ExportSelection(start: start, end: start.addingTimeInterval(held))
    }

    /// Seconds inside the selection that actually hold footage. Overlapping gaps are counted once,
    /// so a timeline that reports the same outage twice cannot drive the total negative.
    public func recordedSeconds(gaps: [FootageGap]) -> TimeInterval {
        let overlaps = gaps
            .compactMap { gap -> TimeRange? in
                let from = max(gap.range.start, start)
                let until = min(gap.range.end, end)
                return from < until ? TimeRange(start: from, end: until) : nil
            }
            .sorted { $0.start < $1.start }

        var missing: TimeInterval = 0
        var cursor: Date?
        for overlap in overlaps {
            let from = max(overlap.start, cursor ?? overlap.start)
            guard overlap.end > from else { continue }
            missing += overlap.end.timeIntervalSince(from)
            cursor = overlap.end
        }
        return max(0, duration - missing)
    }

    /// Whether the server has anything to cut. The one condition that makes a selection invalid —
    /// spanning a gap does not, because the export is simply shorter than the range.
    public func hasRecording(gaps: [FootageGap]) -> Bool {
        recordedSeconds(gaps: gaps) > 0
    }

    public func isStartAtHistory(of span: TimeRange) -> Bool {
        start <= span.start.ceilingToSecond
    }

    public func isEndAtLiveEdge(of span: TimeRange) -> Bool {
        end >= span.end.flooredToSecond
    }

    public var isAtMinimumLength: Bool {
        duration <= Self.minimumDuration
    }
}

private extension Date {
    /// Toward the past — matching the server's own truncation.
    var flooredToSecond: Date { Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down)) }
    /// Toward the future — for the *earliest* bound, where flooring would name a second that sits
    /// before the footage begins.
    var ceilingToSecond: Date { Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.up)) }
}
