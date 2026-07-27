import CamerasEntities

/// Assembles a camera's full-resolution playback for one window — the stream to play plus the
/// wall-clock mapping built from the footage that window actually holds.
public struct GetCameraRecordings: Sendable {
    private let repository: any CameraRecordingsRepository

    public init(repository: any CameraRecordingsRepository) {
        self.repository = repository
    }

    public func execute(for camera: CameraName, in window: TimeRange) async throws(TimelineError) -> RecordingPlayback {
        let segments = try await repository.segments(for: camera, in: window)
        return RecordingPlayback(
            source: repository.playbackSource(for: camera, in: window),
            timeline: RecordingTimeline(window: window, segments: segments)
        )
    }
}
