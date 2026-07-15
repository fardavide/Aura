/// The boundary the Cameras feature depends on to read the user's camera groups. Implemented in
/// the Data layer (the Frigate adapter) — the Domain knows nothing of how it's fetched.
public protocol CameraGroupsRepository: Sendable {
    func groups() async throws(CamerasError) -> [CameraGroup]
}
