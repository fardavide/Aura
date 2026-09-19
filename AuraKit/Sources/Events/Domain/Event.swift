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
    /// The verdict already on record with the server, from this device, another one, or Frigate's
    /// own web UI. `nil` means none has been given — the only state in which one can still be sent,
    /// since the server refuses a second. This is the server's memory, not ours.
    public let verdict: DetectionVerdict?
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
        verdict: DetectionVerdict?,
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
        self.verdict = verdict
        self.score = score
        self.zones = zones
    }

    /// A full re-init with a different verdict — `Event` is immutable, so writing one back after a
    /// report has a single place to change rather than repeating every field at the call site.
    public func withVerdict(_ verdict: DetectionVerdict) -> Event {
        Event(
            id: id,
            camera: camera,
            label: label,
            severity: severity,
            subLabel: subLabel,
            startTime: startTime,
            endTime: endTime,
            hasClip: hasClip,
            hasSnapshot: hasSnapshot,
            isObjectDetection: isObjectDetection,
            verdict: verdict,
            score: score,
            zones: zones
        )
    }
}
