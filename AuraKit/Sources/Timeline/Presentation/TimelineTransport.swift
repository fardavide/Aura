import Foundation
import Observation

import TimelineDomain

/// The Timeline's transport: play/pause and the speed ladder, driving the one shared `ScrubClock`
/// that the scrubber, the readout and every camera tile already follow.
///
/// Playback is a *clock*, not a player. Nothing here streams anything — advancing the shared instant
/// is what makes the tiles move, so the whole grid stays synchronised by construction rather than by
/// keeping N players in step with one another.
@Observable
@MainActor
public final class TimelineTransport {
    public private(set) var isPlaying = false
    public private(set) var speed: PlaybackSpeed = .oneX

    private let clock: ScrubClock
    private let now: @MainActor () -> Date
    private var gaps: [FootageGap] = []
    private var span: TimeRange

    /// How close to the live edge counts as parked on it — the playhead the auto-refresh follow
    /// leaves behind sits within sub-second drift of it.
    private static let liveEdgeTolerance: TimeInterval = 1
    /// How far back pressing play from the live edge rewinds. Nothing is recorded past the edge, so
    /// playing from it would stop on the first tick; back up far enough to actually watch something.
    private static let liveEdgeRewind: TimeInterval = 60

    public init(clock: ScrubClock, now: @escaping @MainActor () -> Date, span: TimeRange) {
        self.clock = clock
        self.now = now
        self.span = span
    }

    public func togglePlayPause() {
        guard !isPlaying else {
            isPlaying = false
            return
        }
        // Starting from the live edge would stop again immediately — there is no footage past it.
        if span.end.timeIntervalSince(clock.instant) <= Self.liveEdgeTolerance {
            clock.scrub(to: span.clamp(span.end.addingTimeInterval(-Self.liveEdgeRewind)))
        }
        isPlaying = true
    }

    public func select(_ speed: PlaybackSpeed) {
        self.speed = speed
    }

    /// Moves the playhead by `seconds` of wall-clock time. Unlike playing, this does not step over
    /// gaps: a deliberate ten seconds back means ten seconds back, even into a stretch with nothing
    /// recorded, which is also how the user leaves one.
    public func skip(by seconds: TimeInterval) {
        clock.scrub(to: span.clamp(clock.instant.addingTimeInterval(seconds)))
    }

    /// Hands the playhead back to the user — the scrubber and the transport would otherwise both
    /// drive the clock, and the drag would fight the tick.
    public func pause() {
        isPlaying = false
    }

    /// Runs the playhead for as long as the screen is on: each tick advances by the real time that
    /// actually elapsed, so a slow tick loses no wall-clock time and the readout tracks the footage
    /// rather than the tick rate. The owning `.task` cancels this when the view disappears.
    public func run(tick: Duration = .milliseconds(100)) async {
        var last = now()
        while !Task.isCancelled {
            try? await Task.sleep(for: tick)
            let current = now()
            advance(byRealSeconds: current.timeIntervalSince(last))
            // Advanced or not, the tick is spent: a paused stretch must not accumulate into a jump
            // when playback resumes.
            last = current
        }
    }

    /// Keeps playback bounded by the footage the screen currently knows about — the span's live edge
    /// grows with every auto-refresh, which is what lets playback carry on into newly recorded time.
    func update(gaps: [FootageGap], span: TimeRange) {
        self.gaps = gaps
        self.span = span
    }

    func advance(byRealSeconds seconds: TimeInterval) {
        guard isPlaying, seconds > 0 else { return }
        switch TimelinePlayhead.advance(
            from: clock.instant,
            byRealSeconds: seconds,
            at: speed,
            over: gaps,
            liveEdge: span.end
        ) {
        case .moved(let instant):
            clock.scrub(to: instant)
        case .reachedLiveEdge(let instant):
            clock.scrub(to: instant)
            isPlaying = false
        }
    }
}
