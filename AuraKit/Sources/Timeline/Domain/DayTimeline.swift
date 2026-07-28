import Foundation

/// Everything the day timeline overlays on one time axis: activity markers, the motion strip,
/// and the no-footage gaps.
public struct DayTimeline: Equatable, Sendable {
    public let markers: [ReviewMarker]
    public let motion: [MotionBucket]
    public let gaps: [FootageGap]

    public init(markers: [ReviewMarker], motion: [MotionBucket], gaps: [FootageGap]) {
        self.markers = markers
        self.motion = motion
        self.gaps = gaps
    }

    /// Folds one fetched window into the timeline. The slice is the fresh truth for its window —
    /// everything inside is replaced, everything outside is kept — so windows can land in any
    /// order and a refresh can re-read just the live edge. An in-progress marker reaches to the
    /// present, so any window past its start supersedes the cached copy. Slice content is clipped
    /// to the window first: the server answers overlap queries with items that spill past the
    /// window's edges, and whatever falls outside belongs to some other window's read.
    public func replacing(_ slice: DayTimelineSlice) -> DayTimeline {
        let window = slice.window
        let mergedMarkers = markers.filter { !$0.overlaps(window) }
            + slice.overlays.markers.filter { $0.overlaps(window) }
        let mergedMotion = motion.filter { !window.contains($0.time) }
            + slice.overlays.motion.filter { window.contains($0.time) }
        let mergedGaps = gaps.flatMap { $0.clipped(outside: window) }
            + slice.overlays.gaps.compactMap { $0.clipped(to: window) }
        return DayTimeline(
            markers: mergedMarkers.sorted { $0.start < $1.start },
            motion: mergedMotion.sorted { $0.time < $1.time },
            gaps: coalesced(mergedGaps.sorted { $0.range.start < $1.range.start })
        )
    }
}

private extension ReviewMarker {
    /// Whether any part of the marker falls inside `window`. An in-progress marker runs to the
    /// present, so it overlaps every window past its start.
    func overlaps(_ window: TimeRange) -> Bool {
        start < window.end && (end ?? .distantFuture) > window.start
    }
}

private extension FootageGap {
    /// The parts of the gap outside `window` — the cached pieces a fresh window must not disturb.
    func clipped(outside window: TimeRange) -> [FootageGap] {
        var pieces: [FootageGap] = []
        if range.start < window.start {
            pieces.append(FootageGap(range: TimeRange(start: range.start, end: min(range.end, window.start))))
        }
        if range.end > window.end {
            pieces.append(FootageGap(range: TimeRange(start: max(range.start, window.end), end: range.end)))
        }
        return pieces
    }

    /// The part of the gap inside `window`, if any.
    func clipped(to window: TimeRange) -> FootageGap? {
        let start = max(range.start, window.start)
        let end = min(range.end, window.end)
        guard start < end else { return nil }
        return FootageGap(range: TimeRange(start: start, end: end))
    }
}

/// Welds gaps that touch or overlap back into one — a gap crossing a window seam arrives as two
/// pieces, one from each side's read. Expects the gaps sorted by start.
private func coalesced(_ gaps: [FootageGap]) -> [FootageGap] {
    var welded: [FootageGap] = []
    for gap in gaps {
        if let last = welded.last, gap.range.start <= last.range.end {
            welded[welded.count - 1] = FootageGap(
                range: TimeRange(start: last.range.start, end: max(last.range.end, gap.range.end))
            )
        } else {
            welded.append(gap)
        }
    }
    return welded
}
