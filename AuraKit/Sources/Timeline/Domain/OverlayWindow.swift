import Foundation

/// Chooses the bounded windows the day-timeline overlay reads (markers, motion, gaps) run over.
///
/// Frigate answers the motion and gap queries by walking every recording row in the window — the
/// gaps endpoint doing that walk on the API's own event loop — so a single multi-day query can
/// freeze the whole server for its duration (verified against v0.17.2; see
/// `frigate-integration.md`). Day-sized windows keep each walk short, and issuing them one at a
/// time leaves the server free to answer everyone else in between.
public enum OverlayWindow {
    /// The most a single overlay query may cover.
    public static let maxLength: TimeInterval = 86_400

    /// Splits `range` into windows of at most a day, newest first, meeting on whole epoch
    /// seconds — the server quantises to whole seconds, so a fractional seam would come back
    /// double-counted on one side or with a hairline hole on the other. The newest window keeps
    /// the range's own live edge.
    public static func windows(covering range: TimeRange) -> [TimeRange] {
        var windows: [TimeRange] = []
        var end = range.end
        while end > range.start {
            let start = Swift.max(
                range.start,
                Date(timeIntervalSince1970: (end.timeIntervalSince1970 - maxLength).rounded(.down))
            )
            windows.append(TimeRange(start: start, end: end))
            end = start
        }
        return windows
    }

    /// The bucket duration for a span: coarser for wider spans so the motion strip stays at about
    /// two thousand points, never finer than a minute. Whole seconds, because that is what the
    /// server takes — and it must be derived from the *full* span, not per window, so every
    /// window of one span comes back at the same resolution.
    public static func bucketDuration(for span: TimeRange) -> TimeInterval {
        Swift.max(60, (span.end.timeIntervalSince(span.start) / 2000).rounded(.down))
    }

    /// The window a periodic refresh re-reads: from one bucket before the previous live edge — so
    /// the bucket that edge cut through is re-evaluated whole, and the trailing "not recorded
    /// yet" gap is re-judged — plus a recording segment's worth for footage the recorder had not
    /// yet written when the last read ran, up to the present. History further back is settled and
    /// is never re-read.
    public static func refresh(previousEnd: Date, now: Date, bucket: TimeInterval) -> TimeRange {
        TimeRange(start: previousEnd.addingTimeInterval(-(bucket + 60)), end: now)
    }
}
