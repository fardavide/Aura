/// Why fetching cameras failed, in domain terms — no HTTP or Frigate vocabulary.
public enum CamerasError: Error, Equatable, Sendable {
    case unreachable
    case notAuthorized
    case serverUnavailable
    case invalidData
    case unknown
}
