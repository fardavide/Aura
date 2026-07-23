import Foundation

import CamerasDomain
import CommonFrigate
import CommonNetwork

/// Reads the activity Frigate is currently tracking from `/api/review`, keeping the in-progress
/// items. The name carries the Frigate detail — `CameraActivityRepository` is the abstraction the
/// rest of the app depends on.
public struct FrigateCameraActivityRepository: CameraActivityRepository {
    private let config: ServerConfig
    private let api: FrigateApiClient
    private let now: @Sendable () -> Date

    public init(config: ServerConfig, httpClient: any HttpClient, now: @escaping @Sendable () -> Date) {
        self.config = config
        api = FrigateApiClient(config: config, httpClient: httpClient)
        self.now = now
    }

    public func activeActivity() async throws(CamerasError) -> [CameraActivity] {
        let before = now()
        let after = before.addingTimeInterval(-activityWindow)
        let data = try await get(FrigateReviewUrl.review(
            base: config.baseUrl,
            after: after.timeIntervalSince1970,
            before: before.timeIntervalSince1970
        ))
        do {
            return try JSONDecoder().decode([ReviewItemDto].self, from: data).toActiveActivity()
        } catch {
            throw CamerasError.invalidData
        }
    }

    private func get(_ url: URL) async throws(CamerasError) -> Data {
        do {
            return try await api.get(url)
        } catch {
            throw CamerasError(error)
        }
    }
}

/// The lookback for in-progress activity — wide enough to catch an item that began a while ago but
/// hasn't ended, small enough to keep the review payload light.
private let activityWindow: TimeInterval = 6 * 3600
