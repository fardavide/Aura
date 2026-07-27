import CamerasDomain

/// Replays the canned emissions in order, then finishes. Passing none stands in for a read that
/// failed — the stream carries no errors, so "nothing arrives" is what a failure looks like.
public final class FakeCameraGroupsRepository: CameraGroupsRepository, @unchecked Sendable {
    private let emissions: [[CameraGroup]]

    public init(_ emissions: [CameraGroup]...) {
        self.emissions = emissions
    }

    public func observeGroups() -> AsyncStream<[CameraGroup]> {
        AsyncStream { continuation in
            for emission in emissions {
                continuation.yield(emission)
            }
            continuation.finish()
        }
    }
}
