import Foundation

import TimelineDomain

/// How the timeline's playhead moves while the transport is running: forward at the chosen speed,
/// over the stretches with nothing recorded, and no further than the newest footage.
///
/// Gaps are stepped over rather than played through — sitting inside one would show every tile the
/// same frozen frame for as long as the gap lasts, which reads as a hung player. Pure, so the rule
/// is testable without a clock or a player.
enum TimelinePlayhead {
    enum Step: Equatable {
        case moved(Date)
        /// Nothing past this instant has been recorded yet, so playback has nowhere left to go.
        case reachedLiveEdge(Date)
    }

    static func advance(
        from instant: Date,
        byRealSeconds seconds: TimeInterval,
        at speed: PlaybackSpeed,
        over gaps: [FootageGap],
        liveEdge: Date
    ) -> Step {
        var target = instant.addingTimeInterval(seconds * speed.rawValue)
        // Ascending, so a jump landing in the following gap is stepped over by the next iteration —
        // adjacent gaps are cleared in one pass, and the pass always terminates.
        for gap in gaps.sorted(by: { $0.range.start < $1.range.start }) where gap.range.contains(target) {
            target = gap.range.end
        }
        guard target < liveEdge else { return .reachedLiveEdge(liveEdge) }
        return .moved(target)
    }
}
