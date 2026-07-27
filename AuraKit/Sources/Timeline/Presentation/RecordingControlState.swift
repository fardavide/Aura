import Foundation

/// The transport state `RecordingControlBar` renders — decoupled from `RecordingPlayerViewModel` so
/// the bar is a pure function of value inputs (and can be snapshot-tested with literal state, no
/// `AVPlayer`).
public struct RecordingControlState: Equatable, Sendable {
    public let instant: Date
    public let isPlaying: Bool
    public let speed: PlaybackSpeed
    /// Whether the playhead sits over recorded footage; false inside a gap, where the bar says so.
    public let hasFootage: Bool
    /// False for an hour holding no footage at all: there is nothing to start or speed up, though
    /// the skips stay live so the hour can be left.
    public let isPlayable: Bool

    public init(instant: Date, isPlaying: Bool, speed: PlaybackSpeed, hasFootage: Bool, isPlayable: Bool) {
        self.instant = instant
        self.isPlaying = isPlaying
        self.speed = speed
        self.hasFootage = hasFootage
        self.isPlayable = isPlayable
    }
}
