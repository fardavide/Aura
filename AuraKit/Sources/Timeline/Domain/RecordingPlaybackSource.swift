import CamerasEntities

public enum RecordingPlaybackSource: Equatable, Sendable {
    case stream(CameraStreamSource)
    case clips([RecordingClip])
}
