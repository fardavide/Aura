import Foundation

import CamerasEntities

/// Activity Frigate is tracking on a camera *right now* — an in-progress review item. An `alert`
/// (person / car, by Frigate's defaults) or a lower-priority `detection`; drives the badge on a
/// live camera tile. `startedAt` lets the grid keep the most recent when a camera has several.
public struct CameraActivity: Equatable, Hashable, Sendable {
    public let camera: CameraName
    public let label: String
    public let severity: Severity
    public let startedAt: Date

    public init(camera: CameraName, label: String, severity: Severity, startedAt: Date) {
        self.camera = camera
        self.label = label
        self.severity = severity
        self.startedAt = startedAt
    }

    public enum Severity: Equatable, Hashable, Sendable {
        case alert
        case detection
    }
}
