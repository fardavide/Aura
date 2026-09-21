/// Answers one question about one address: is the Frigate server responding there, right now?
///
/// Implemented in the Data layer against the server's cheapest endpoint. It never throws — a
/// probe that fails, is refused, or runs out of time all mean the same thing to the caller, and
/// `false` is a normal answer rather than an error to surface.
public protocol ServerReachabilityProbing: Sendable {
    /// Must return within `timeout` whatever the network does: on a foreign Wi-Fi a private
    /// address is usually dropped in silence rather than refused, so the implementation cannot
    /// rely on the transport failing promptly.
    func canReach(_ server: ActiveServer, within timeout: Duration) async -> Bool
}
