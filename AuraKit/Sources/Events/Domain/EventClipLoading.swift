import Foundation

/// Downloads an event's recorded clip. Implemented in the Data layer over the authenticated
/// HTTP client (the same path that serves REST + thumbnails), so the player can play a local
/// file instead of streaming with fragile auth/byte-range requests. Returns nil on failure.
public protocol EventClipLoading: Sendable {
    func downloadClip(for event: Event) async -> Data?
}
