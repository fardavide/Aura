import Foundation

import CamerasEntities

/// A detected event (object/motion) on a camera.
public struct Event: Equatable, Hashable, Sendable, Identifiable {
    public let id: EventId
    public let camera: CameraName
    public let label: String
    public let severity: EventSeverity
    public let subLabel: String?
    public let startTime: Date
    /// Nil while the event is still in progress.
    public let endTime: Date?
    public let hasClip: Bool
    public let hasSnapshot: Bool
    public let score: Double?
    public let zones: [String]

    public init(
        id: EventId,
        camera: CameraName,
        label: String,
        severity: EventSeverity,
        subLabel: String?,
        startTime: Date,
        endTime: Date?,
        hasClip: Bool,
        hasSnapshot: Bool,
        score: Double?,
        zones: [String]
    ) {
        self.id = id
        self.camera = camera
        self.label = label
        self.severity = severity
        self.subLabel = subLabel
        self.startTime = startTime
        self.endTime = endTime
        self.hasClip = hasClip
        self.hasSnapshot = hasSnapshot
        self.score = score
        self.zones = zones
    }
}
