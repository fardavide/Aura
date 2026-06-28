import Foundation
import Observation

/// The one shared scrub position the day timeline writes and every preview tile reads.
@Observable
@MainActor
public final class ScrubClock {
    public private(set) var instant: Date
    public private(set) var isScrubbing = false

    public init(instant: Date) {
        self.instant = instant
    }

    public func beginScrub() {
        isScrubbing = true
    }

    public func scrub(to instant: Date) {
        self.instant = instant
    }

    public func endScrub() {
        isScrubbing = false
    }
}
