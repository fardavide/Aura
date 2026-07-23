import Foundation

import CamerasDomain
import CommonFrigate
import CommonNetwork

/// Reads cameras from a Frigate server. The name carries the implementation detail —
/// `CamerasRepository` is the abstraction the rest of the app depends on.
public struct FrigateCamerasRepository: CamerasRepository {
    private let config: ServerConfig
    private let httpClient: any HttpClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        self.httpClient = httpClient
    }

    public func cameras() async throws(CamerasError) -> [Camera] {
        let data = try await get(.config)
        do {
            return try JSONDecoder().decode(ConfigDto.self, from: data).toCameras()
        } catch {
            throw CamerasError.invalidData
        }
    }

    /// Bounds the config read like the timeline reads (`timelineRequestTimeout`): the Timeline
    /// screen's first load gates its full-screen spinner on this fetch, so a server that accepts
    /// the connection but never responds must fail into `.unreachable` (which auto-refresh
    /// retries) instead of holding the spinner for URLSession's 60s default per attempt.
    private static let requestTimeout: TimeInterval = 15

    private func get(_ endpoint: FrigateEndpoint) async throws(CamerasError) -> Data {
        var request = URLRequest(url: endpoint.url(base: config.baseUrl))
        request.timeoutInterval = Self.requestTimeout
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
