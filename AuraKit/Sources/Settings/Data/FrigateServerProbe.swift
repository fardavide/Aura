import Foundation

import CommonFrigate
import CommonNetwork
import SettingsDomain

/// Asks `GET /api/version` whether Frigate is answering at an address, and never waits longer
/// than it was given.
///
/// It builds its own request rather than going through `FrigateApiClient`: that client's 15s
/// bound is right for a read whose result the user is waiting on, and hopelessly wrong for a
/// check that sits in front of the first paint. The deadline is enforced by racing the request
/// against a sleep, because `URLRequest.timeoutInterval` is an *idle* timer — and the case this
/// has to be fast in, a private address on a foreign network, is precisely the one where packets
/// are dropped in silence and nothing ever arrives to time out against.
public struct FrigateServerProbe: ServerReachabilityProbing {
    private let httpClient: any HttpClient

    public init(httpClient: any HttpClient) {
        self.httpClient = httpClient
    }

    public func canReach(_ server: ActiveServer, within timeout: Duration) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await answersAsFrigate(server, within: timeout) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    /// Requires more than "something answered": on a café's Wi-Fi the home router's own IP is
    /// perfectly likely to have *a* web server on it, and switching the whole app onto a stranger's
    /// host is a worse failure than falling back to remote. Frigate answers this endpoint with a
    /// bare version string, so anything that isn't a short line starting with a digit — an HTML
    /// login page, a captive portal — is not the server we are looking for.
    private func answersAsFrigate(_ server: ActiveServer, within timeout: Duration) async -> Bool {
        var request = URLRequest(url: FrigateEndpoint.version.url(base: ServerConfig(server).baseUrl))
        request.timeoutInterval = timeout.timeInterval
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        if let auth = AuthorizationHeader.basic(username: server.username, password: server.password) {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        guard
            let (body, response) = try? await httpClient.data(for: request),
            (200...299).contains(response.statusCode),
            body.count <= Self.maximumVersionLength,
            let version = String(data: body, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return false
        }
        return version.first?.isNumber == true
    }

    private static let maximumVersionLength = 64
}

private extension Duration {
    var timeInterval: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
