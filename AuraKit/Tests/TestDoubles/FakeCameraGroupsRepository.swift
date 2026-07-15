import CamerasDomain

/// Replays a canned result; `result` is mutable so a test can change the outcome between calls.
public final class FakeCameraGroupsRepository: CameraGroupsRepository, @unchecked Sendable {
    public var result: Result<[CameraGroup], CamerasError>

    public init(_ result: Result<[CameraGroup], CamerasError>) {
        self.result = result
    }

    public func groups() async throws(CamerasError) -> [CameraGroup] {
        try result.get()
    }
}
