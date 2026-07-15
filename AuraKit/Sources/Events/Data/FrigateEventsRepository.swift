import Foundation

import CommonFrigate
import CommonNetwork
import EventsDomain

/// Reads events from Frigate's `/api/events`, decoding + mapping to the domain.
public struct FrigateEventsRepository: EventsRepository {
    private let config: ServerConfig
    private let httpClient: any HttpClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        self.httpClient = httpClient
    }

    public func events(limit: Int) async throws(EventsError) -> [Event] {
        let data = try await get(.events(limit: limit, after: nil))
        do {
            return try JSONDecoder().decode([EventDto].self, from: data).toEvents()
        } catch {
            throw EventsError.invalidData
        }
    }

    private func get(_ endpoint: FrigateEndpoint) async throws(EventsError) -> Data {
        var request = URLRequest(url: endpoint.url(base: config.baseUrl))
        if let auth = AuthorizationHeader.basic(username: config.username, password: config.password) {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await httpClient.data(for: request)
        } catch {
            throw EventsError.unreachable
        }
        switch response.statusCode {
        case 200...299: return data
        case 401, 403: throw EventsError.notAuthorized
        case 500...599: throw EventsError.serverUnavailable
        default: throw EventsError.unknown
        }
    }
}
