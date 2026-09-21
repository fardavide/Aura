import Foundation

import SettingsDomain

/// Drives the local-network availability stream by hand: observers get the current value first,
/// then whatever `send` pushes — so a test can walk an install from Wi-Fi to cellular and back.
public final class FakeNetworkPathObserver: NetworkPathObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var isAvailable: Bool
    private var continuations: [AsyncStream<Bool>.Continuation] = []

    public init(isLocalNetworkAvailable: Bool) {
        isAvailable = isLocalNetworkAvailable
    }

    public func send(_ isLocalNetworkAvailable: Bool) {
        let observers = lock.withLock {
            isAvailable = isLocalNetworkAvailable
            return continuations
        }
        for continuation in observers { continuation.yield(isLocalNetworkAvailable) }
    }

    /// Ends every observer's stream — how a test asserts that nothing *else* was emitted.
    public func finish() {
        let observers = lock.withLock {
            let observers = continuations
            continuations = []
            return observers
        }
        for continuation in observers { continuation.finish() }
    }

    public func localNetworkAvailability() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            lock.withLock {
                continuation.yield(isAvailable)
                continuations.append(continuation)
            }
        }
    }
}
