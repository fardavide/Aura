import Foundation

/// The boundary the Events feature depends on to read events. Implemented in the Data layer.
public protocol EventsRepository: Sendable {

    /// Returns at most `limit` events. `before` is the paging cursor: only events that started
    /// strictly before it are returned, so passing an instant just past the oldest page already
    /// held walks backwards through history. `nil` asks for the newest events.
    func events(limit: Int, before: Date?) async throws(EventsError) -> [Event]
}
