import Foundation
import Network
import Synchronization

import SettingsDomain

/// Reports Wi-Fi / wired availability from the system's path monitor.
///
/// It watches the two interface types with their **own** monitors instead of reading the default
/// path's interface, because a VPN is the normal state here rather than an exotic one — Tailscale
/// is the whole reason a remote address exists. With a tunnel up the default path runs over a
/// `utun` interface, so asking it "are you Wi-Fi?" answers no while the Wi-Fi underneath is
/// perfectly able to reach the LAN. A monitor pinned to an interface type answers about that
/// interface, tunnel or no tunnel.
public struct SystemNetworkPathObserver: NetworkPathObserving {

    public init() {}

    public func localNetworkAvailability() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let availability = InterfaceAvailability { continuation.yield($0) }
            // `NWPathMonitor` delivers on a dispatch queue by contract — this is the API's own
            // shape, not concurrency plumbing we chose.
            let queue = DispatchQueue(label: "fardavide.Aura.network-path")
            let monitors = Self.localInterfaces.map { interface in
                let monitor = NWPathMonitor(requiredInterfaceType: interface)
                // Starting a monitor delivers the current path, which is what seeds the stream's
                // first value — no separate read needed.
                monitor.pathUpdateHandler = { path in
                    availability.set(interface, isSatisfied: path.status == .satisfied)
                }
                monitor.start(queue: queue)
                return monitor
            }
            continuation.onTermination = { _ in
                for monitor in monitors { monitor.cancel() }
            }
        }
    }

    /// The interfaces that can carry a home-LAN address. Cellular is deliberately absent — that is
    /// the case the whole check exists to answer "no" to, instantly.
    private static let localInterfaces: [NWInterface.InterfaceType] = [.wifi, .wiredEthernet]
}

/// Collapses several interface monitors into one answer — available when *any* of them has a
/// path — and emits only when that answer changes, so a Wi-Fi hiccup that leaves the verdict
/// unchanged costs nothing downstream.
private final class InterfaceAvailability: Sendable {
    /// `emitted` starts `nil` rather than `false` so the **first** path update always reaches the
    /// stream. Seeding it with `false` would swallow the "no Wi-Fi at all" case, and a stream that
    /// never emits leaves the app resolving forever instead of falling back to the remote address.
    private let state = Mutex<(satisfied: Set<NWInterface.InterfaceType>, emitted: Bool?)>(
        (satisfied: [], emitted: nil)
    )
    private let emit: @Sendable (Bool) -> Void

    init(emit: @escaping @Sendable (Bool) -> Void) {
        self.emit = emit
    }

    func set(_ interface: NWInterface.InterfaceType, isSatisfied: Bool) {
        let changed = state.withLock { state -> Bool? in
            if isSatisfied {
                state.satisfied.insert(interface)
            } else {
                state.satisfied.remove(interface)
            }
            let isAvailable = !state.satisfied.isEmpty
            guard isAvailable != state.emitted else { return nil }
            state.emitted = isAvailable
            return isAvailable
        }
        guard let changed else { return }
        emit(changed)
    }
}
