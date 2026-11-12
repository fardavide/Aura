import Foundation
import SwiftUI

/// Haptic ticks spaced in points so their cadence is independent of zoom.
struct ScrubFeedback: Equatable {
    private(set) var tick = 0
    private var tracking = Tracking.idle

    mutating func update(for phase: ScrollPhase, at position: CGFloat) {
        switch phase {
        case .interacting:
            begin(at: position)
        case .decelerating:
            break
        case .idle, .tracking, .animating:
            end()
        }
    }

    mutating func begin(at position: CGFloat) {
        tracking = .active(lastTickPosition: position, nextTickAt: .now)
    }

    mutating func move(to position: CGFloat, at now: ContinuousClock.Instant = .now) {
        guard case let .active(lastTickPosition, nextTickAt) = tracking,
              abs(position - lastTickPosition) >= 16,
              now >= nextTickAt else { return }
        tracking = .active(lastTickPosition: position, nextTickAt: now.advanced(by: .milliseconds(80)))
        tick &+= 1
    }

    mutating func end() {
        tracking = .idle
    }

    private enum Tracking: Equatable {
        case idle
        case active(lastTickPosition: CGFloat, nextTickAt: ContinuousClock.Instant)
    }
}
