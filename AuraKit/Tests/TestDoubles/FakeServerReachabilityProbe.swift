import Foundation

import SettingsDomain

/// Answers every probe the same way, recording what it was asked — so a test can assert both the
/// route that was chosen and that the cheap paths didn't probe at all.
public final class FakeServerReachabilityProbe: ServerReachabilityProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var answer: Bool
    private var calls: [(server: ActiveServer, timeout: Duration)] = []

    public var probedServers: [ActiveServer] { lock.withLock { calls.map(\.server) } }
    public var probedTimeouts: [Duration] { lock.withLock { calls.map(\.timeout) } }

    public init(isReachable: Bool) {
        answer = isReachable
    }

    public func setReachable(_ isReachable: Bool) {
        lock.withLock { answer = isReachable }
    }

    public func canReach(_ server: ActiveServer, within timeout: Duration) async -> Bool {
        lock.withLock {
            calls.append((server: server, timeout: timeout))
            return answer
        }
    }
}
