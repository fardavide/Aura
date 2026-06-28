import Foundation

import CommonFrigate
import CommonNetwork
import EventsDomain

/// Fetches an event's thumbnail through the authenticated HTTP client.
public struct FrigateEventThumbnailLoader: EventThumbnailLoading {
    private let config: ServerConfig
    private let httpClient: any HttpClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        self.httpClient = httpClient
    }

    public func thumbnail(for event: EventId) async -> Data? {
        let url = FrigateMediaUrl.thumbnail(base: config.baseUrl, eventId: event.value)
        var request = URLRequest(url: url)
        if let auth = AuthorizationHeader.basic(username: config.username, password: config.password) {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        guard
            let (data, response) = try? await httpClient.data(for: request),
            (200...299).contains(response.statusCode)
        else {
            return nil
        }
        return data
    }
}
