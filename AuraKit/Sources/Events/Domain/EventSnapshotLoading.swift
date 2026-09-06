import Foundation

/// Loads an event's full-frame still (the hero image) — separate from `EventThumbnailLoading`
/// (interface segregation: rows need the object-crop thumbnail, the hero needs the full frame).
/// Implemented in the Data layer with an authenticated request; returns nil on any failure so the
/// hero falls back to the thumbnail.
public protocol EventSnapshotLoading: Sendable {
    func snapshot(for event: EventId) async -> Data?
}
