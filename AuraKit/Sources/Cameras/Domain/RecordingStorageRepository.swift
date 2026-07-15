/// The boundary the Cameras feature depends on to read recording-disk status. Implemented in the
/// Data layer (the Frigate adapter, over `/api/stats` + config) — the Domain knows nothing of how
/// it's fetched.
public protocol RecordingStorageRepository: Sendable {
    func storage() async throws(CamerasError) -> RecordingStorage
}
