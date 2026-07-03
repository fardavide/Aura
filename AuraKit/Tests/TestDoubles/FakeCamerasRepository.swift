import CamerasDomain

/// Replays a canned result; `result` is mutable so a test can change the outcome between calls
/// (e.g. a refresh that fails after a successful load). Tracks how many times it was queried.
public final class FakeCamerasRepository: CamerasRepository, @unchecked Sendable {
    public var result: Result<[Camera], CamerasError>
    public private(set) var fetchCount = 0

    public init(_ result: Result<[Camera], CamerasError>) {
        self.result = result
    }

    public func cameras() async throws(CamerasError) -> [Camera] {
        fetchCount += 1
        return try result.get()
    }
}
