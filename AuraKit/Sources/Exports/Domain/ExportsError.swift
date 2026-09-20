/// Why an exports read or a download failed, in domain terms.
public enum ExportsError: Error, Equatable, Sendable {
    case unreachable
    case notAuthorized
    /// The server understood the request and refused it — repeating it verbatim fails the same way,
    /// so the UI must not offer a retry.
    case rejected
    case serverUnavailable
    case invalidData
    case unknown
}
