import Foundation

/// The transport seam: performs a request and returns the body plus the HTTP response.
/// Implementations stay free of any Frigate or domain knowledge; status handling and
/// error mapping belong to the caller (the Data layer).
public protocol HttpClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct UrlSessionHttpClient: HttpClient {
    /// Internal (not private) so a test can pin the bounded configuration.
    let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForResource = Self.resourceTimeout
        session = URLSession(configuration: configuration)
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    /// Wall-clock cap on a whole transfer. The per-request 15s bound is an *idle* timer, so a
    /// connection dribbling ≥1 byte per window evades it and holds a gating load open forever —
    /// this backstop ends it. Deliberately generous: it must never abort the largest legitimate
    /// transfer on this session, a full event clip downloaded for playback over a slow remote
    /// link (VOD/HLS playback rides AVFoundation's own sessions, not this one).
    private static let resourceTimeout: TimeInterval = 600
}
