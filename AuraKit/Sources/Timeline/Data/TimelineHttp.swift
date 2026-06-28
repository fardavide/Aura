import Foundation

import CommonFrigate
import CommonNetwork
import TimelineDomain

/// Authenticated GET returning the body, mapping transport/status failures to `TimelineError`.
/// Shared by the timeline repository and preview provider (the same ladder the other features use).
func authorizedData(
    url: URL,
    config: ServerConfig,
    httpClient: any HttpClient
) async throws(TimelineError) -> Data {
    var request = URLRequest(url: url)
    if let auth = AuthorizationHeader.basic(username: config.username, password: config.password) {
        request.setValue(auth, forHTTPHeaderField: "Authorization")
    }
    let data: Data
    let response: HTTPURLResponse
    do {
        (data, response) = try await httpClient.data(for: request)
    } catch {
        throw TimelineError.unreachable
    }
    switch response.statusCode {
    case 200...299: return data
    case 401, 403: throw TimelineError.notAuthorized
    case 500...599: throw TimelineError.serverUnavailable
    default: throw TimelineError.unknown
    }
}

/// The auth headers to attach to media (player/image) requests, or empty when no credentials.
func authorizationHeaders(for config: ServerConfig) -> [String: String] {
    guard let auth = AuthorizationHeader.basic(username: config.username, password: config.password) else {
        return [:]
    }
    return ["Authorization": auth]
}
