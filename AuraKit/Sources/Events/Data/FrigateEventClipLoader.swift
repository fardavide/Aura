import Foundation

import CommonFrigate
import CommonNetwork
import EventsDomain

/// Downloads an event's `clip.mp4` through the authenticated HTTP client.
public struct FrigateEventClipLoader: EventClipLoading {
    private let config: ServerConfig
    private let httpClient: any HttpClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        self.httpClient = httpClient
    }

    public func downloadClip(for event: Event) async -> Data? {
        let url = FrigateMediaUrl.clip(base: config.baseUrl, eventId: event.id.value)
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
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
