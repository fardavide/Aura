import Foundation

import CamerasDomain

/// Serves one fixed image (or `nil` — the placeholder path) for every camera, recording which
/// cameras were asked for.
public final class FakeCameraImageLoader: CameraImageLoading, @unchecked Sendable {
    public var image: Data?
    public private(set) var requested: [CameraName] = []

    public init(image: Data? = nil) {
        self.image = image
    }

    public func previewImage(for camera: CameraName) async -> Data? {
        requested.append(camera)
        return image
    }
}
