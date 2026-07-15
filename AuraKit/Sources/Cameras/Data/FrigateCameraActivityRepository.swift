import Foundation

import CamerasDomain
import CommonFrigate
import CommonNetwork

/// Reads the activity Frigate is currently tracking from `/api/review`, keeping the in-progress
/// items. The name carries the Frigate detail — `CameraActivityRepository` is the abstraction the
/// rest of the app depends on.
public struct FrigateCameraActivityRepository: CameraActivityRepository {
    private let config: ServerConfig
    private let httpClient: any HttpClient
    private let now: @Sendable () -> Date

    public init(config: ServerConfig, httpClient: any HttpClient, now: @escaping @Sendable () -> Date) {
        self.config = config
        self.httpClient = httpClient
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
        var request = URLRequest(url: url)
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

/// The lookback for in-progress activity — wide enough to catch an item that began a while ago but
/// hasn't ended, small enough to keep the review payload light.
private let activityWindow: TimeInterval = 6 * 3600
