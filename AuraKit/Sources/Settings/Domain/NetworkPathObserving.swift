/// Reports whether the device is attached to a network that could plausibly carry a home-LAN
/// address — Wi-Fi or wired. Implemented in the Data layer over the system's path monitor.
///
/// This is the cheap half of choosing a route: on cellular (or with no network at all) a LAN
/// address cannot work, so the answer needs no probe and costs nothing.
public protocol NetworkPathObserving: Sendable {
    /// The current answer immediately, then one value per change — the same "current value first"
    /// contract the observed settings preferences use.
    func localNetworkAvailability() -> AsyncStream<Bool>
}
