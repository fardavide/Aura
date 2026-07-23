import Foundation

import CamerasDomain
import CommonFrigate
import CommonNetwork

/// Reads the user's camera groups from `GET /api/config`. The name carries the Frigate detail —
/// `CameraGroupsRepository` is the abstraction the rest of the app depends on.
public struct FrigateCameraGroupsRepository: CameraGroupsRepository {
    private let config: ServerConfig
    private let httpClient: any HttpClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        self.httpClient = httpClient
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
