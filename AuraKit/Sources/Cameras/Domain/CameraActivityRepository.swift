/// The boundary the Cameras feature depends on to read in-progress activity. Implemented in the
/// Data layer (the Frigate adapter) — the Domain knows nothing of how it's fetched.
public protocol CameraActivityRepository: Sendable {
    func activeActivity() async throws(CamerasError) -> [CameraActivity]
}
