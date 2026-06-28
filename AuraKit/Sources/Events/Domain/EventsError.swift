/// Why fetching events failed, in domain terms.
public enum EventsError: Error, Equatable, Sendable {
    case unreachable
    case notAuthorized
    case serverUnavailable
    case invalidData
    case unknown
}
