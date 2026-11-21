/// Streams the address the app should be talking to: the current choice immediately, then a new
/// one whenever the device's network changes under it.
///
/// The rule is *prefer local, fall back to remote*, and it is deliberately cheap:
/// - one address configured → use it without a probe;
/// - no Wi-Fi or wired interface (cellular, or offline) → remote, no probe, no wait — a private
///   address cannot work there, so asking would only burn the timeout;
/// - otherwise → one short probe of the local address, and remote the moment it doesn't answer.
///
/// The remote address is never probed. It is the fallback, so a failure there has no second
/// choice to offer — the screens already report an unreachable server, and probing it first would
/// only add a round trip to every launch away from home.
///
/// Only *changes* are emitted, so the common case (arriving home, leaving home) rebuilds the graph
/// once and a flapping interface that resolves the same way rebuilds it not at all.
public struct ObserveActiveServer: Sendable {
    private let probe: any ServerReachabilityProbing
    private let networkPaths: any NetworkPathObserving
    private let localProbeTimeout: Duration

    public init(
        probe: any ServerReachabilityProbing,
        networkPaths: any NetworkPathObserving,
        localProbeTimeout: Duration
    ) {
        self.probe = probe
        self.networkPaths = networkPaths
        self.localProbeTimeout = localProbeTimeout
    }

    public func execute(for connection: ConnectionSettings) -> AsyncStream<ActiveServer> {
        AsyncStream { continuation in
            // No second address means no choice, so the answer is known before anything is
            // observed — which also keeps every install that predates the local address off the
            // path monitor entirely, rather than making its first paint wait on a callback.
            guard let local = connection.localServer, let remote = connection.remoteServer else {
                continuation.yield(connection.fallbackServer)
                continuation.finish()
                return
            }
            let task = Task {
                var emitted: ActiveServer?
                for await hasLocalNetwork in networkPaths.localNetworkAvailability() {
                    let resolved = if hasLocalNetwork, await probe.canReach(local, within: localProbeTimeout) {
                        local
                    } else {
                        remote
                    }
                    guard resolved != emitted else { continue }
                    emitted = resolved
                    continuation.yield(resolved)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
