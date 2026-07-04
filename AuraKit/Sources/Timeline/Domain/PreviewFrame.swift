import Foundation

import CamerasEntities

/// A single current-hour preview frame for one camera (the live hour has no mp4 yet).
public struct PreviewFrame: Equatable, Sendable {
    public let camera: CameraName
    public let time: Date
    /// Frigate's preview-frame filename, e.g. `preview_<camera>-<ts>.webp`.
    public let fileName: String

    public init(camera: CameraName, time: Date, fileName: String) {
        self.camera = camera
        self.time = time
        self.fileName = fileName
    }
}
