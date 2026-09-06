import Foundation

/// The events that started within one hour-of-day band, newest first.
public struct EventHourGroup: Equatable, Sendable, Identifiable {
    public let hourStart: Date
    public let events: [Event]

    public init(hourStart: Date, events: [Event]) {
        self.hourStart = hourStart
        self.events = events
    }

    public var id: Date { hourStart }
}
