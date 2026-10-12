import Foundation

/// Chooses the bounded window that full-resolution playback runs over: a clock hour for HLS,
/// or two minutes for fast-forward compositions so preparing their original assets stays bounded.
public enum RecordingWindow {
    public static let length: TimeInterval = 3600

    /// The aligned window holding `instant`, on whole epoch seconds so the segment query, media
    /// path, and the wall-clock mapping all agree on the same integers.
    ///
    /// Deliberately independent of the present. The window is both the unit of playback **and its
    /// identity** — "am I still in the loaded window?" is asked on every seek — so an end that
    /// crept along with the clock would make the in-progress hour a different window every second:
    /// each skip would refetch, and reaching the end of the stream would reload the same hour from
    /// the top. The hour after the last recorded one simply comes back empty, which is the honest
    /// answer and the one the live-edge check reads.
    public static func containing(_ instant: Date, mode: RecordingMode = .standard) -> TimeRange {
        // Composition readiness inspects original files. Keep fast-forward loads small enough
        // to avoid preparing hundreds of assets before the first frame can appear.
        let length: TimeInterval = switch mode {
        case .standard: Self.length
        case .fastForward: 120
        }
        let start = (instant.timeIntervalSince1970 / length).rounded(.down) * length
        return TimeRange(
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: start + length)
        )
    }
}
