import Foundation

/// Loads an event's thumbnail image. Implemented in the Data layer with an authenticated
/// request; returns nil on any failure so the UI shows a placeholder.
public protocol EventThumbnailLoading: Sendable {
    func thumbnail(for event: EventId) async -> Data?
}
