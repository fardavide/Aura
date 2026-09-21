/// Streams the address the app should be talking to: the current choice immediately, then a new
/// one whenever the device's network changes under it.
///
/// The rule is *prefer local, fall back to remote*, and it is deliberately cheap:
/// - no local address configured → remote, no probe, no wait;
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
            guard connection.local != nil else {
                continuation.yield(connection.remoteServer)
                continuation.finish()
                return
            }
            let task = Task {
                var emitted: ActiveServer?
                for await hasLocalNetwork in networkPaths.localNetworkAvailability() {
                    let resolved = await resolve(connection, hasLocalNetwork: hasLocalNetwork)
                    guard resolved != emitted else { continue }
                    emitted = resolved
                    continuation.yield(resolved)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func resolve(_ connection: ConnectionSettings, hasLocalNetwork: Bool) async -> ActiveServer {
        guard hasLocalNetwork, let local = connection.localServer else { return connection.remoteServer }
        return await probe.canReach(local, within: localProbeTimeout) ? local : connection.remoteServer
    }
}
