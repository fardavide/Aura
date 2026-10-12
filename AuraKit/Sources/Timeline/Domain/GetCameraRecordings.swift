import CamerasEntities

/// Assembles a camera's full-resolution playback for one window — the stream to play plus the
/// wall-clock mapping built from the footage that window actually holds.
public struct GetCameraRecordings: Sendable {
    private let repository: any CameraRecordingsRepository

    public init(repository: any CameraRecordingsRepository) {
        self.repository = repository
    }

    public func execute(for camera: CameraName, in window: TimeRange, mode: RecordingMode = .standard) async throws(TimelineError) -> RecordingPlayback {
        switch mode {
        case .standard:
            let segments = try await repository.segments(for: camera, in: window)
            return RecordingPlayback(
                source: .stream(repository.playbackSource(for: camera, in: window)),
                timeline: RecordingTimeline(window: window, segments: segments)
            )
        case .fastForward:
            let clips = try await repository.clips(for: camera, in: window)
            return RecordingPlayback(
                source: .clips(clips),
                timeline: RecordingTimeline(window: window, segments: clips.map {
                    RecordingSegment(range: $0.range, duration: $0.duration)
                })
            )
        }
    }
}
