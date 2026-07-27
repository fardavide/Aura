import Foundation

/// Maps between wall-clock instants and the playback stream's own clock, for one bounded window.
///
/// The stream welds the window's segments into one continuous run with every gap removed, so
/// player time is the sum of the preceding clips' durations and drifts further from wall-clock
/// time the more footage is missing. Every seek and every readout has to cross that divide, which
/// is what this type exists to do.
///
/// Both mappings are total. An instant inside a gap collapses onto the gap's trailing edge — the
/// gap has no length in the stream, so that is where playback genuinely resumes — and instants
/// outside the footage clamp to the ends. Whether an instant has footage at all is the separate
/// question `hasFootage(at:)` answers, so the UI can say so rather than silently show the wrong
/// moment.
public struct RecordingTimeline: Equatable, Sendable {
    public let window: TimeRange
    /// Playable seconds in the window — the footage, not the window's wall-clock span.
    public let playableDuration: TimeInterval
    private let clips: [PlayableClip]

    public init(window: TimeRange, segments: [RecordingSegment]) {
        self.window = window
        var offset: TimeInterval = 0
        var built: [PlayableClip] = []
        for segment in segments.sorted(by: { $0.range.start < $1.range.start }) {
            // The server trims a segment's *duration* by however much it overhangs the window,
            // then drops what is left if it falls outside the clip bounds it will serve.
            let head = max(0, window.start.timeIntervalSince(segment.range.start))
            let tail = max(0, segment.range.end.timeIntervalSince(window.end))
            let duration = segment.duration - head - tail
            let start = max(segment.range.start, window.start)
            let end = min(segment.range.end, window.end)
            guard start < end, duration >= shortestServedClip, duration < longestServedClip else { continue }
            built.append(PlayableClip(start: start, end: end, duration: duration, offset: offset))
            offset += duration
        }
        clips = built
        playableDuration = offset
    }

    public func hasFootage(at instant: Date) -> Bool {
        clips.contains { instant >= $0.start && instant < $0.end }
    }

    /// Where `instant` sits in the stream: the footage before it, with any gaps counting for
    /// nothing. Past the last segment this is the end of the stream.
    public func playerTime(at instant: Date) -> TimeInterval {
        var elapsed: TimeInterval = 0
        for clip in clips {
            if instant < clip.start { return elapsed }
            if instant < clip.end { return clip.offset + min(instant.timeIntervalSince(clip.start), clip.duration) }
            elapsed = clip.offset + clip.duration
        }
        return elapsed
    }

    /// The wall-clock instant `playerTime` seconds into the stream — the inverse of
    /// `playerTime(at:)` over instants that have footage.
    public func instant(atPlayerTime playerTime: TimeInterval) -> Date {
        guard let last = clips.last else { return window.start }
        let target = min(max(playerTime, 0), playableDuration)
        for clip in clips where target < clip.offset + clip.duration {
            return min(clip.start.addingTimeInterval(target - clip.offset), clip.end)
        }
        return last.end
    }
}

/// One segment as the stream actually renders it: trimmed to the window, carrying the cumulative
/// player time it begins at.
private struct PlayableClip: Equatable {
    let start: Date
    let end: Date
    /// Trimmed encoded length — what advances player time, which the wall-clock span may not match.
    let duration: TimeInterval
    let offset: TimeInterval
}

/// The bounds the server serves a clip within; anything outside is omitted from the stream, so a
/// mapping that counted it would run every later instant off by that much.
private let shortestServedClip: TimeInterval = 0.1
private let longestServedClip: TimeInterval = 600
