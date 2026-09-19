import Foundation

import CommonNetwork

/// The one authed GET every Frigate JSON/media read goes through: attaches Basic auth, bounds the
/// request with a timeout, and maps transport/status failures into `FrigateApiError` for each
/// feature's Data layer to translate into its own domain error. Deliberately **not**
/// request-coalescing — consolidating the repeated per-screen `/api/config` reads stays a separate
/// follow-up (see `status.md`).
public struct FrigateApiClient: Sendable {
    private let config: ServerConfig
    private let httpClient: any HttpClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        self.httpClient = httpClient
    }

    public func get(_ url: URL) async throws(FrigateApiError) -> Data {
        try await send("GET", url: url, body: nil)
    }

    /// A JSON write. `body` is sent verbatim — the caller owns the encoding, since the two Frigate
    /// write endpoints the app uses take hand-shaped one-key objects rather than a domain model.
    public func post(_ url: URL, body: Data) async throws(FrigateApiError) -> Data {
        try await send("POST", url: url, body: body)
    }

    /// A bodyless write — Frigate's false-positive submission takes its only argument in the path.
    public func put(_ url: URL) async throws(FrigateApiError) -> Data {
        try await send("PUT", url: url, body: nil)
    }

    private func send(_ method: String, url: URL, body: Data?) async throws(FrigateApiError) -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = Self.requestTimeout
        if let auth = AuthorizationHeader.basic(username: config.username, password: config.password) {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await httpClient.data(for: request)
        } catch {
            throw FrigateApiError.unreachable
        }
        switch response.statusCode {
        case 200...299: return data
        case 400: throw FrigateApiError.rejected
        case 401, 403: throw FrigateApiError.notAuthorized
        case 500...599: throw FrigateApiError.serverUnavailable
        default: throw FrigateApiError.unknown
        }
    }

    /// Bounds every read so a server that accepts the connection but never responds fails fast
    /// instead of holding a gating load for URLSession's 60s default — a non-erroring stall slips
    /// past every best-effort `try?`. Generous next to Frigate's sub-second JSON, so it only trips
    /// a genuine hang; and it is an *idle* timeout (reset whenever bytes arrive), so a large clip
    /// download on a slow link is not cut off. Tune up if a real deployment reads slower.
    private static let requestTimeout: TimeInterval = 15
}

/// How a Frigate read failed, in transport vocabulary. Each feature's Data layer maps these into
/// its own domain error at the boundary, so no Domain ever sees them.
public enum FrigateApiError: Error, Equatable, Sendable {
    case unreachable
    case notAuthorized
    /// The server understood the request and refused it — repeating it verbatim will fail the same
    /// way, so it is never a retry-worthy failure.
    case rejected
    case serverUnavailable
    case unknown
}
