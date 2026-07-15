import Foundation

import CamerasDomain
import CamerasEntities

/// Serves one fixed image (or `nil` — the offline path) for every camera, recording which cameras
/// were asked for. Safe under concurrent calls — the grid loads tile previews in parallel — so the
/// recorded list is guarded by a lock.
public final class FakeCameraImageLoader: CameraImageLoading, @unchecked Sendable {
    public var image: Data?

    private let lock = NSLock()
    private var requestedCameras: [CameraName] = []

    public var requested: [CameraName] {
        lock.withLock { requestedCameras }
    }

    public init(image: Data? = nil) {
        self.image = image
    }

    public func previewImage(for camera: CameraName) async -> Data? {
        lock.withLock { requestedCameras.append(camera) }
        return image
    }
}
