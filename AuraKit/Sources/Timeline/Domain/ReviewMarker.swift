import Foundation

import CamerasEntities

/// How significant a review item is: `alert` (person/car by default) vs `detection` (the rest).
public enum ReviewSeverity: Equatable, Sendable {
    case alert
    case detection
}

/// An activity period shown as a marker on the day timeline. `end` is nil while in progress.
public struct ReviewMarker: Equatable, Sendable {
    public let camera: CameraName
    public let start: Date
    public let end: Date?
    public let severity: ReviewSeverity
    /// The tracked object, capitalized — "Person", "Car" — or the severity word when Frigate
    /// attached none.
    public let label: String

    public init(camera: CameraName, start: Date, end: Date?, severity: ReviewSeverity, label: String) {
        self.camera = camera
        self.start = start
        self.end = end
        self.severity = severity
        self.label = label
    }
}
