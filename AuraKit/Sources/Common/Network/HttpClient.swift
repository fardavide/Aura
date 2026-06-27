import Foundation

/// The transport seam: performs a request and returns the body plus the HTTP response.
/// Implementations stay free of any Frigate or domain knowledge; status handling and
/// error mapping belong to the caller (the Data layer).
public protocol HttpClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct UrlSessionHttpClient: HttpClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
