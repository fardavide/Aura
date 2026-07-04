import CamerasDomain
import CamerasEntities

/// Returns one fixed stream source for every camera; `nil` (the default) means no stream —
/// the detail view model resolves to its unavailable state.
public final class FakeCameraStreamProvider: CameraStreamProviding, @unchecked Sendable {
    public var source: CameraStreamSource?

    public init(_ source: CameraStreamSource? = nil) {
        self.source = source
    }

    public func streamSource(for camera: Camera) -> CameraStreamSource? { source }
}
