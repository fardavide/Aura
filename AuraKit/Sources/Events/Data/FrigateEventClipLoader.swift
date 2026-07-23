import Foundation

import CommonFrigate
import CommonNetwork
import EventsDomain

/// Downloads an event's `clip.mp4` through the authenticated HTTP client.
public struct FrigateEventClipLoader: EventClipLoading {
    private let config: ServerConfig
    private let api: FrigateApiClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        api = FrigateApiClient(config: config, httpClient: httpClient)
    }

    public func downloadClip(for event: Event) async -> Data? {
        try? await api.get(FrigateMediaUrl.clip(base: config.baseUrl, eventId: event.id.value))
    }
}
