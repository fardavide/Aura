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

    /// Whether re-sending the identical request could succeed. This is what decides whether a
    /// failure is offered a `Try again` control at all — a retry that could only fail the same way
    /// is a dead control, so the UI removes it rather than disabling it.
    ///
    /// A rejection is the server's considered "no" to *this* range and stays no until the
    /// selection changes; bad credentials and an unreadable answer are equally unchanged by
    /// pressing again. Everything else is transport, and transport recovers.
    public var isRetryable: Bool {
        switch self {
        case .rejected, .notAuthorized, .invalidData: false
        case .unreachable, .serverUnavailable, .unknown: true
        }
    }
}
