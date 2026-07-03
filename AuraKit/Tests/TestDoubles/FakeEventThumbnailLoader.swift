import Foundation

import EventsDomain

/// Serves one fixed thumbnail (or `nil` — the placeholder path) for every event.
public final class FakeEventThumbnailLoader: EventThumbnailLoading, @unchecked Sendable {
    public var thumbnail: Data?

    public init(thumbnail: Data? = nil) {
        self.thumbnail = thumbnail
    }

    public func thumbnail(for event: EventId) async -> Data? { thumbnail }
}
