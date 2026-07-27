import CamerasEntities

/// Everything full-resolution playback needs for one window: the authenticated stream to play and
/// the mapping from the timeline's wall clock onto that stream's own clock.
public struct RecordingPlayback: Equatable, Sendable {
    public let source: CameraStreamSource
    public let timeline: RecordingTimeline

    public init(source: CameraStreamSource, timeline: RecordingTimeline) {
        self.source = source
        self.timeline = timeline
    }
}
