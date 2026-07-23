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
    private let api: FrigateApiClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        api = FrigateApiClient(config: config, httpClient: httpClient)
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
        do {
            return try await api.get(endpoint.url(base: config.baseUrl))
        } catch {
            throw CamerasError(error)
        }
    }
}
