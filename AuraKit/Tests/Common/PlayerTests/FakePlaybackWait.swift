import Foundation

@MainActor
final class FakePlaybackWait {
    let requests: AsyncStream<Duration>

    private let requested: AsyncStream<Duration>.Continuation
    private var pending: [CheckedContinuation<Void, Never>] = []

    init() {
        (requests, requested) = AsyncStream<Duration>.makeStream()
    }

    func wait(_ duration: Duration) async throws {
        await withCheckedContinuation { continuation in
            pending.append(continuation)
            requested.yield(duration)
        }
    }

    func elapse() {
        let continuations = pending
        pending.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    func elapseNext() {
        pending.removeFirst().resume()
    }
}
