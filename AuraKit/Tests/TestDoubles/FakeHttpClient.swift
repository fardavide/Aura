import Foundation
import Synchronization

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
    private let sequence: [Outcome]
    // Locked because tests fetch concurrently — an unsynchronized array append corrupts the heap.
    private let requests = Mutex<[URLRequest]>([])

    public var lastRequest: URLRequest? { requests.withLock { $0.last } }
    /// How many requests were made — proves a shared read fetches once instead of per caller.
    public var requestCount: Int { requests.withLock { $0.count } }
    /// Every requested URL, for asserting how often one particular endpoint was hit.
    public var requestedUrls: [String] {
        requests.withLock { $0.map { $0.url?.absoluteString ?? "" } }
    }

    public init(_ outcome: Outcome) {
        routes = [(match: "", outcome: outcome)]
        sequence = []
    }

    public init(routes: [(String, Outcome)]) {
        self.routes = routes.map { (match: $0.0, outcome: $0.1) }
        sequence = []
    }

    /// Answers the n-th request with the n-th outcome, repeating the last one once exhausted — for
    /// a repeated read whose response changes between fetches (a refresh).
    public init(sequence: [Outcome]) {
        routes = []
        self.sequence = sequence
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let attempt = requests.withLock { requests -> Int in
            requests.append(request)
            return requests.count - 1
        }
        let urlString = request.url?.absoluteString ?? ""
        let outcome = if sequence.isEmpty {
            (routes.first { !$0.match.isEmpty && urlString.contains($0.match) } ?? routes[0]).outcome
        } else {
            sequence[min(attempt, sequence.count - 1)]
        }
        switch outcome {
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
