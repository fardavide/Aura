import Foundation

import CommonNetwork

/// Canned `HttpClient` for repository tests — records the last request and replays a stubbed
/// outcome. The single-outcome init answers every request the same way; the routed init picks
/// the first route whose substring matches the request URL (falling back to the first route),
/// so a multi-endpoint fetch can return a different body per path.
public final class FakeHttpClient: HttpClient, @unchecked Sendable {
    public enum Outcome {
        case response(status: Int, body: Data)
        case failure(any Error)
    }

    private let routes: [(match: String, outcome: Outcome)]
    public private(set) var lastRequest: URLRequest?

    public init(_ outcome: Outcome) {
        routes = [(match: "", outcome: outcome)]
    }

    public init(routes: [(String, Outcome)]) {
        self.routes = routes.map { (match: $0.0, outcome: $0.1) }
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let urlString = request.url?.absoluteString ?? ""
        let route = routes.first { !$0.match.isEmpty && urlString.contains($0.match) } ?? routes[0]
        switch route.outcome {
        case let .response(status, body):
            let response = HTTPURLResponse(
                url: request.url ?? URL(filePath: "/unused"),
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
