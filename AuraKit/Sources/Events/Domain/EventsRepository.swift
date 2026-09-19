import Foundation

/// The boundary the Events feature depends on to read events. Implemented in the Data layer.
public protocol EventsRepository: Sendable {

    /// Returns at most `limit` events. `before` is the paging cursor: only events that started
    /// strictly before it are returned, so passing an instant just past the oldest page already
    /// held walks backwards through history. `nil` asks for the newest events.
    func events(limit: Int, before: Date?) async throws(EventsError) -> [Event]

    /// Re-reads one event. The copy a list hands to a detail screen ages the moment a verdict is
    /// given — here or in a browser — and only the server knows the current answer.
    func event(id: EventId) async throws(EventsError) -> Event

    /// Whether this server accepts detection feedback at all — it is a paid add-on, off by default.
    func isDetectionFeedbackEnabled() async throws(EventsError) -> Bool

    /// Sends the user's verdict on one detection, adding its snapshot to the training dataset.
    func submit(_ verdict: DetectionVerdict, for event: EventId) async throws(EventsError)
}
