import Foundation

import CamerasDomain
import CommonFrigate
import CommonNetwork

/// Reads the labels of the events since a moment from `GET /api/events?after=`, for the grid's
/// "today" tally. The name carries the Frigate detail — `TodayEventsRepository` is the abstraction
/// the rest of the app depends on.
public struct FrigateTodayEventsRepository: TodayEventsRepository {
    private let config: ServerConfig
    private let api: FrigateApiClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        api = FrigateApiClient(config: config, httpClient: httpClient)
    }

    public func labels(since: Date) async throws(CamerasError) -> [String] {
        let data = try await get(.events(limit: eventsLimit, after: since.timeIntervalSince1970))
        do {
            return try JSONDecoder().decode([EventLabelDto].self, from: data).map(\.label)
        } catch {
            throw CamerasError.invalidData
        }
    }

    private func get(_ endpoint: FrigateEndpoint) async throws(CamerasError) -> Data {
        do {
            return try await api.get(endpoint.url(base: config.baseUrl))
        } catch {
            throw CamerasError(error)
        }
    }
}

/// A day of a home's events fits comfortably; enough to tally without paging.
private let eventsLimit = 500
