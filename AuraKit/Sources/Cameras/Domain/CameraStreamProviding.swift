/// Resolves a camera's live stream. Implemented in the Data layer (the Frigate/go2rtc
/// adapter); returns nil when the camera has no stream configured.
public protocol CameraStreamProviding: Sendable {
    func streamSource(for camera: Camera) -> CameraStreamSource?
}
