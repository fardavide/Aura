import Foundation

/// The boundary the Cameras feature depends on to tally today's events. Returns the label of each
/// event that started at or after `since` (one entry per event); the use case aggregates them.
/// Implemented in the Data layer over `/api/events` — the Domain knows nothing of how it's fetched.
public protocol TodayEventsRepository: Sendable {
    func labels(since: Date) async throws(CamerasError) -> [String]
}
