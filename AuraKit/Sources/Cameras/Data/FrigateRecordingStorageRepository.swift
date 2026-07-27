import Foundation

import CamerasDomain
import CommonFrigate
import CommonNetwork

/// Reads recording-disk status from Frigate: the retention knobs come from the shared `/api/config`
/// body, the disk figures from `GET /api/stats`. Two sources because Frigate splits the data; the
/// stats are re-read on every config emission, since free space is exactly what moves.
public struct FrigateRecordingStorageRepository: RecordingStorageRepository {
    private let config: ServerConfig
    private let api: FrigateApiClient
    private let configProvider: FrigateConfigProvider

    public init(config: ServerConfig, httpClient: any HttpClient, configProvider: FrigateConfigProvider) {
        self.config = config
        self.configProvider = configProvider
        api = FrigateApiClient(config: config, httpClient: httpClient)
    }

    public func observeStorage() -> AsyncStream<RecordingStorage?> {
        AsyncStream { continuation in
            let task = Task {
                var hasEmitted = false
                for await outcome in await configProvider.observeConfig() {
                    let storage = if case .success(let configData) = outcome {
                        await read(configData)
                    } else {
                        RecordingStorage?.none
                    }
                    if let storage {
                        continuation.yield(storage)
                        hasEmitted = true
                    } else if !hasEmitted {
                        // Resolve the first read even when it failed, so a caller waiting on it
                        // gets an empty slot rather than hanging.
                        continuation.yield(nil)
                        hasEmitted = true
                    }
                    // A later failure emits nothing: the figures already on screen stand.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Combines the retention knobs from the config body with a fresh `/api/stats` read. Any trip
    /// along the way yields nothing rather than a half-filled value.
    private func read(_ configData: Data) async -> RecordingStorage? {
        guard
            let record = try? JSONDecoder().decode(RecordConfigDto.self, from: configData),
            let statsData = try? await api.get(FrigateEndpoint.stats.url(base: config.baseUrl)),
            let stats = try? JSONDecoder().decode(StatsDto.self, from: statsData)
        else {
            return nil
        }
        return stats.toRecordingStorage(record: record)
    }
}
