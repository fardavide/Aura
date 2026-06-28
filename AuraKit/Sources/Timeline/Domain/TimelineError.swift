/// Why a timeline fetch failed, in domain terms — no HTTP or Frigate vocabulary.
public enum TimelineError: Error, Equatable, Sendable {
    case unreachable
    case notAuthorized
    case serverUnavailable
    case invalidData
    case unknown
}
