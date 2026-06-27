import Foundation

import CommonFrigate
import CommonNetwork

/// A representative `/api/config` body covering the cases the mapper must handle:
/// an enabled camera with friendly name + streams, a disabled camera, and a camera
/// with no `enabled` field (defaults to enabled) and empty streams.
let configJson = """
{
  "cameras": {
    "driveway": {
      "enabled": true,
      "friendly_name": "Driveway",
      "live": { "streams": { "Driveway HD": "driveway", "Driveway SD": "driveway_sub" } }
    },
    "garage": {
      "enabled": false
    },
    "porch": {
      "friendly_name": "Front Porch",
      "live": { "streams": {} }
    }
  }
}
"""

extension ServerConfig {
    static let test = ServerConfig(
        scheme: .http,
        host: "frigate.test",
        port: 5000,
        username: nil,
        password: nil
    )
}

/// Canned `HttpClient` for repository tests — records the request and replays a stubbed outcome.
final class FakeHttpClient: HttpClient, @unchecked Sendable {
    enum Outcome {
        case response(status: Int, body: Data)
        case failure(any Error)
    }

    private let outcome: Outcome
    private(set) var lastRequest: URLRequest?

    init(_ outcome: Outcome) {
        self.outcome = outcome
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        switch outcome {
        case let .response(status, body):
            let url = request.url ?? URL(string: "http://frigate.test")!
            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (body, response)
        case let .failure(error):
            throw error
        }
    }
}
