import Foundation

import CommonFrigate
import CommonNetwork
import EventsDomain

/// Fetches an event's thumbnail through the authenticated HTTP client.
public struct FrigateEventThumbnailLoader: EventThumbnailLoading {
    private let config: ServerConfig
    private let api: FrigateApiClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        api = FrigateApiClient(config: config, httpClient: httpClient)
    }

    public func thumbnail(for event: EventId) async -> Data? {
        try? await api.get(FrigateMediaUrl.thumbnail(base: config.baseUrl, eventId: event.value))
    }
}
