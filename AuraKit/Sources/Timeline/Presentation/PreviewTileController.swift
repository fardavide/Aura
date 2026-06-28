import Foundation

/// Coalesces a stream of scrub targets into at most one in-flight preview update, always
/// honoring the latest target — the per-tile in-flight guard (no debounce timer), mirroring
/// Frigate's web client. The actual seek/load is delegated to a `PreviewScrubber`.
///
/// While an update is in flight, new targets only update `pending`; on completion it re-applies
/// the latest pending target, but only if it drifts past `tolerance` (so tiny moves are skipped).
@MainActor
final class PreviewTileController {
    private let scrubber: any PreviewScrubber
    private let tolerance: TimeInterval

    private var isSeeking = false
    private var pending: Date?
    private var lastApplied: Date?

    init(scrubber: any PreviewScrubber, tolerance: TimeInterval) {
        self.scrubber = scrubber
        self.tolerance = tolerance
    }

    func scrub(to time: Date) {
        if isSeeking {
            pending = time
        } else {
            apply(time)
        }
    }

    private func apply(_ time: Date) {
        isSeeking = true
        lastApplied = time
        pending = nil
        scrubber.scrub(to: time) { [weak self] in
            self?.finish()
        }
    }

    private func finish() {
        isSeeking = false
        guard
            let next = pending,
            let last = lastApplied,
            abs(next.timeIntervalSince(last)) >= tolerance
        else {
            pending = nil
            return
        }
        apply(next)
    }
}
