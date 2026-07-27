/// The recording-disk status for the grid's summary card, re-emitted whenever the server config is
/// re-read. Best-effort by construction: the stream simply stays quiet when a read fails, so the
/// card keeps the last good figures instead of blanking.
public struct ObserveRecordingStorage: Sendable {
    private let repository: any RecordingStorageRepository

    public init(repository: any RecordingStorageRepository) {
        self.repository = repository
    }

    public func execute() -> AsyncStream<RecordingStorage?> {
        repository.observeStorage()
    }
}
