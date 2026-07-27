import Foundation

/// Chooses the bounded window that full-resolution playback runs over. A window is one clock hour
/// of epoch time: the server refuses a playlist past a couple of hours, so a whole day is never
/// requested — playback swaps windows at the hour instead.
public enum RecordingWindow {
    public static let length: TimeInterval = 3600

    /// The clock hour holding `instant`, on whole epoch seconds so the segment query, the playlist
    /// path, and the wall-clock mapping all agree on the same integers.
    ///
    /// Deliberately independent of the present. The window is both the unit of playback **and its
    /// identity** — "am I still in the loaded window?" is asked on every seek — so an end that
    /// crept along with the clock would make the in-progress hour a different window every second:
    /// each skip would refetch, and reaching the end of the stream would reload the same hour from
    /// the top. The hour after the last recorded one simply comes back empty, which is the honest
    /// answer and the one the live-edge check reads.
    public static func containing(_ instant: Date) -> TimeRange {
        let start = (instant.timeIntervalSince1970 / length).rounded(.down) * length
        return TimeRange(
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: start + length)
        )
    }
}
