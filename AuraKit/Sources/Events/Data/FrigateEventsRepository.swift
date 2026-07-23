import Foundation

import CommonFrigate
import CommonNetwork
import EventsDomain

/// Reads events from Frigate's `/api/events`, decoding + mapping to the domain.
public struct FrigateEventsRepository: EventsRepository {
    private let config: ServerConfig
    private let api: FrigateApiClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        api = FrigateApiClient(config: config, httpClient: httpClient)
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
        do {
            return try await api.get(endpoint.url(base: config.baseUrl))
        } catch {
            throw EventsError(error)
        }
    }
}

private extension EventsError {
    /// Translates the shared Frigate transport error into the feature's domain error at the Data
    /// boundary, so the Domain never sees Frigate vocabulary.
    init(_ error: FrigateApiError) {
        switch error {
        case .unreachable: self = .unreachable
        case .notAuthorized: self = .notAuthorized
        case .serverUnavailable: self = .serverUnavailable
        case .unknown: self = .unknown
        }
    }
}
