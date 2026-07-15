/// The recording-disk status for the grid's summary card. Best-effort at the call site: the card
/// degrades gracefully if it throws.
public struct GetRecordingStorage: Sendable {
    private let repository: any RecordingStorageRepository

    public init(repository: any RecordingStorageRepository) {
        self.repository = repository
    }

    public func execute() async throws(CamerasError) -> RecordingStorage {
        try await repository.storage()
    }
}
