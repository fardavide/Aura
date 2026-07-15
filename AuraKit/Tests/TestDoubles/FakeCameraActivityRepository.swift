import CamerasDomain

/// Replays a canned result; `result` is mutable so a test can change the outcome between calls.
public final class FakeCameraActivityRepository: CameraActivityRepository, @unchecked Sendable {
    public var result: Result<[CameraActivity], CamerasError>

    public init(_ result: Result<[CameraActivity], CamerasError>) {
        self.result = result
    }

    public func activeActivity() async throws(CamerasError) -> [CameraActivity] {
        try result.get()
    }
}
