/// The boundary the Cameras feature depends on to read cameras. Implemented in the
/// Data layer (the Frigate adapter) — the Domain knows nothing of how it's fetched.
public protocol CamerasRepository: Sendable {
    func cameras() async throws(CamerasError) -> [Camera]
}
