import CamerasDomain

/// Replays a canned result; `result` is mutable so a test can change the outcome between calls.
public final class FakeRecordingStorageRepository: RecordingStorageRepository, @unchecked Sendable {
    public var result: Result<RecordingStorage, CamerasError>

    public init(_ result: Result<RecordingStorage, CamerasError>) {
        self.result = result
    }

    public func storage() async throws(CamerasError) -> RecordingStorage {
        try result.get()
    }
}
