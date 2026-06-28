import Foundation

/// How significant a review item is: `alert` (person/car by default) vs `detection` (the rest).
public enum ReviewSeverity: Equatable, Sendable {
    case alert
    case detection
}

/// An activity period shown as a marker on the day timeline. `end` is nil while in progress.
public struct ReviewMarker: Equatable, Sendable {
    public let start: Date
    public let end: Date?
    public let severity: ReviewSeverity

    public init(start: Date, end: Date?, severity: ReviewSeverity) {
        self.start = start
        self.end = end
        self.severity = severity
    }
}
