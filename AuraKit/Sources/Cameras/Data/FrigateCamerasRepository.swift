import Foundation

import CamerasDomain
import CommonFrigate
import CommonNetwork

/// Reads cameras from a Frigate server. The name carries the implementation detail —
/// `CamerasRepository` is the abstraction the rest of the app depends on.
public struct FrigateCamerasRepository: CamerasRepository {
    private let config: ServerConfig
    private let api: FrigateApiClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        api = FrigateApiClient(config: config, httpClient: httpClient)
    }

    public func cameras() async throws(CamerasError) -> [Camera] {
        let data = try await get(.config)
        do {
            return try JSONDecoder().decode(ConfigDto.self, from: data).toCameras()
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
