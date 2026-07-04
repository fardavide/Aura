import Foundation

import CamerasEntities

/// A past-hour low-res preview segment for one camera — scrubbed locally by seeking the player.
public struct PreviewClip: Equatable, Sendable {
    public let camera: CameraName
    public let range: TimeRange
    /// Frigate's leading-slash `src` path; resolved to a playable URL in the Data layer.
    public let path: String

    public init(camera: CameraName, range: TimeRange, path: String) {
        self.camera = camera
        self.range = range
        self.path = path
    }

    public func contains(_ time: Date) -> Bool {
        range.contains(time)
    }
}
