import Foundation

import CamerasDomain
import CommonFrigate
import CommonNetwork

/// Reads the user's camera groups from `GET /api/config`. The name carries the Frigate detail —
/// `CameraGroupsRepository` is the abstraction the rest of the app depends on.
public struct FrigateCameraGroupsRepository: CameraGroupsRepository {
    private let config: ServerConfig
    private let api: FrigateApiClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        api = FrigateApiClient(config: config, httpClient: httpClient)
    }

    public func groups() async throws(CamerasError) -> [CameraGroup] {
        let data = try await get(.config)
        do {
            return try JSONDecoder().decode(GroupsConfigDto.self, from: data).toCameraGroups()
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
