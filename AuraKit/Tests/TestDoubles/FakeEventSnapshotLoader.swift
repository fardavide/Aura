import Foundation

import EventsDomain

/// Serves one fixed snapshot (or `nil` — the hero falls back to the thumbnail) for every event.
public final class FakeEventSnapshotLoader: EventSnapshotLoading, @unchecked Sendable {
    public var snapshot: Data?

    public init(snapshot: Data? = nil) {
        self.snapshot = snapshot
    }

    public func snapshot(for event: EventId) async -> Data? { snapshot }
}
