import Foundation

/// One recorded footage segment — the ground truth for what can actually be played back, as
/// opposed to the low-res preview material the scrub grid uses.
///
/// `duration` is the encoded length of the file, which is **not** interchangeable with the span
/// `range` covers: the server builds each playback clip from the duration, so that is what any
/// mapping onto player time has to follow.
public struct RecordingSegment: Equatable, Sendable {
    public let range: TimeRange
    public let duration: TimeInterval

    public init(range: TimeRange, duration: TimeInterval) {
        self.range = range
        self.duration = duration
    }
}
