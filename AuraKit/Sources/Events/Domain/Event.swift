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
    /// A tracked object, as opposed to an audio or manually-created event. Only these carry the
    /// bounding box a verdict is attached to.
    public let isObjectDetection: Bool
    /// Its snapshot is already in the training dataset, from an earlier verdict on this or another
    /// device. Submitting twice is refused by the server, so the screen reports instead of asking.
    public let isSubmittedForTraining: Bool
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
        isObjectDetection: Bool,
        isSubmittedForTraining: Bool,
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
        self.isObjectDetection = isObjectDetection
        self.isSubmittedForTraining = isSubmittedForTraining
        self.score = score
        self.zones = zones
    }
}
