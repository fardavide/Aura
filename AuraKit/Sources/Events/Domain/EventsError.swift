/// Why an events read or write failed, in domain terms.
public enum EventsError: Error, Equatable, Sendable {
    case unreachable
    case notAuthorized
    /// The server understood the request and refused it — for a verdict, the event is not one it
    /// can accept (no clean snapshot kept, or too old to carry a bounding box). Retrying is futile.
    case notAccepted
    case serverUnavailable
    case invalidData
    case unknown
}
