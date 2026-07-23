import Foundation

import CamerasDomain
import CommonFrigate
import CommonNetwork

/// Reads recording-disk status from Frigate: `GET /api/stats` for the disk figures and `GET
/// /api/config` for the retention knobs, combined into one domain value. Two calls because Frigate
/// splits the data across endpoints; both are load-time (not on the grid's refresh loop).
///
/// This re-fetches the heavy `/api/config` that the cameras/groups reads already pull — consolidating
/// the per-screen config reads behind a shared, request-coalescing client is the standing follow-up.
public struct FrigateRecordingStorageRepository: RecordingStorageRepository {
    private let config: ServerConfig
    private let httpClient: any HttpClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        self.httpClient = httpClient
    }

    public func storage() async throws(CamerasError) -> RecordingStorage {
        let statsData = try await get(.stats)
        let configData = try await get(.config)
        do {
            let stats = try JSONDecoder().decode(StatsDto.self, from: statsData)
            let record = try JSONDecoder().decode(RecordConfigDto.self, from: configData)
            return stats.toRecordingStorage(record: record)
        } catch {
            throw CamerasError.invalidData
        }
    }

    private func get(_ endpoint: FrigateEndpoint) async throws(CamerasError) -> Data {
        var request = URLRequest(url: endpoint.url(base: config.baseUrl))
        request.timeoutInterval = 15
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
