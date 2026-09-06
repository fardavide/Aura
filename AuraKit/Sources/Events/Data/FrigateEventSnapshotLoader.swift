import Foundation

import CommonFrigate
import CommonNetwork
import EventsDomain

/// Fetches an event's full-frame still through the authenticated HTTP client.
public struct FrigateEventSnapshotLoader: EventSnapshotLoading {
    private let config: ServerConfig
    private let api: FrigateApiClient
    /// The hero is at most ~390 pt wide; 480 px covers 2× on the widest iPad hero without pulling
    /// a full-resolution still.
    private let snapshotHeight = 480

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        api = FrigateApiClient(config: config, httpClient: httpClient)
    }

    public func snapshot(for event: EventId) async -> Data? {
        try? await api.get(
            FrigateMediaUrl.snapshot(base: config.baseUrl, eventId: event.value, height: snapshotHeight)
        )
    }
}
