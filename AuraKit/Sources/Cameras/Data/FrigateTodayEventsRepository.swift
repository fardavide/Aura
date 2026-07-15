import Foundation

import CamerasDomain
import CommonFrigate
import CommonNetwork

/// Reads the labels of the events since a moment from `GET /api/events?after=`, for the grid's
/// "today" tally. The name carries the Frigate detail — `TodayEventsRepository` is the abstraction
/// the rest of the app depends on.
public struct FrigateTodayEventsRepository: TodayEventsRepository {
    private let config: ServerConfig
    private let httpClient: any HttpClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        self.httpClient = httpClient
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
        var request = URLRequest(url: endpoint.url(base: config.baseUrl))
        if let header = AuthorizationHeader.basic(username: config.username, password: config.password) {
            request.setValue(header, forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await httpClient.data(for: request)
        } catch {
            throw CamerasError.unreachable
        }

        switch response.statusCode {
        case 200...299: return data
        case 401, 403: throw CamerasError.notAuthorized
        case 500...599: throw CamerasError.serverUnavailable
        default: throw CamerasError.unknown
        }
    }
}

/// A day of a home's events fits comfortably; enough to tally without paging.
private let eventsLimit = 500
