import CamerasDomain

/// Replays the canned emissions in order, then finishes. Passing none stands in for a read that
/// failed — the stream carries no errors, so "nothing arrives" is what a failure looks like.
public final class FakeRecordingStorageRepository: RecordingStorageRepository, @unchecked Sendable {
    private let emissions: [RecordingStorage?]

    public init(_ emissions: RecordingStorage?...) {
        self.emissions = emissions
    }

    public func observeStorage() -> AsyncStream<RecordingStorage?> {
        AsyncStream { continuation in
            for emission in emissions {
                continuation.yield(emission)
            }
            continuation.finish()
        }
    }
}
