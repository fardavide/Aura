/// The boundary the Cameras feature depends on to read recording-disk status. Implemented in the
/// Data layer (the Frigate adapter, over `/api/stats` + config) — the Domain knows nothing of how
/// it's fetched.
public protocol RecordingStorageRepository: Sendable {
    /// The disk status as it changes. Instead of an error it emits `nil` — the card's slot simply
    /// has nothing to show — and once a value has been shown a later failed read emits nothing at
    /// all, leaving the last figures in place rather than blanking them.
    func observeStorage() -> AsyncStream<RecordingStorage?>
}
