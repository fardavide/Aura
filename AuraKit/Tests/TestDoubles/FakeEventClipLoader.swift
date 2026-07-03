import Foundation

import EventsDomain

/// Serves one fixed clip download (or `nil` — the failure path) for every event.
public final class FakeEventClipLoader: EventClipLoading, @unchecked Sendable {
    public var clip: Data?

    public init(_ clip: Data? = nil) {
        self.clip = clip
    }

    public func downloadClip(for event: Event) async -> Data? { clip }
}
