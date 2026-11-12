import Foundation

/// Spaced haptic ticks during a manual drag, measured in points so the cadence is independent of zoom.
struct ScrubFeedback: Equatable {
    private(set) var tick = 0
    private var tracking = Tracking.idle

    mutating func begin(at position: CGFloat) {
        tracking = .dragging(lastTickPosition: position, nextTickAt: .now)
    }

    mutating func move(to position: CGFloat, at now: ContinuousClock.Instant = .now) {
        guard case let .dragging(lastTickPosition, nextTickAt) = tracking,
              abs(position - lastTickPosition) >= 24,
              now >= nextTickAt else { return }
        tracking = .dragging(lastTickPosition: position, nextTickAt: now.advanced(by: .milliseconds(80)))
        tick &+= 1
    }

    mutating func end() {
        tracking = .idle
    }

    private enum Tracking: Equatable {
        case idle
        case dragging(lastTickPosition: CGFloat, nextTickAt: ContinuousClock.Instant)
    }
}
