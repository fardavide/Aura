import CamerasEntities

/// Supplies one camera's full-resolution recordings for a bounded window: the segments that say
/// what footage exists, and the playable, authenticated stream covering the same window.
public protocol CameraRecordingsRepository: Sendable {
    func segments(for camera: CameraName, in window: TimeRange) async throws(TimelineError) -> [RecordingSegment]
    func playbackSource(for camera: CameraName, in window: TimeRange) -> CameraStreamSource
}
