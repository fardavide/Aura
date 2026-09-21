import Foundation
import Testing

@testable import TimelineDomain

struct ExportSelectionSeedTests {

    @Test func `given room either side of the playhead then the seed runs 30 seconds back and 60 forward`() {
        let seed = ExportSelection.seeded(around: at(1_000), within: span(0, 10_000))
        #expect(seed == ExportSelection(start: at(970), end: at(1_060)))
        #expect(seed?.duration == 90)
    }

    @Test func `given a playhead near the live edge then the seed clamps to it and is shorter`() {
        let seed = ExportSelection.seeded(around: at(1_000), within: span(0, 1_020))
        #expect(seed == ExportSelection(start: at(970), end: at(1_020)))
    }

    @Test func `given a playhead near the start of history then the seed clamps there`() {
        let seed = ExportSelection.seeded(around: at(1_000), within: span(990, 10_000))
        #expect(seed == ExportSelection(start: at(990), end: at(1_060)))
    }

    @Test func `given a fractional playhead then both seeded bounds are whole seconds`() {
        let seed = ExportSelection.seeded(around: at(1_000.6), within: span(0, 10_000))
        #expect(seed == ExportSelection(start: at(970), end: at(1_060)))
    }

    @Test func `given a span shorter than one second then there is no seed`() {
        #expect(ExportSelection.seeded(around: at(1_000), within: span(1_000, 1_000.5)) == nil)
    }

    @Test func `given a span of exactly one second then the seed fills it`() {
        let seed = ExportSelection.seeded(around: at(1_000), within: span(1_000, 1_001))
        #expect(seed == ExportSelection(start: at(1_000), end: at(1_001)))
    }
}

struct ExportSelectionHandleTests {

    private let span = TimeRange(start: at(0), end: at(10_000))
    private let selection = ExportSelection(start: at(1_000), end: at(1_090))

    @Test func `given a new start before the end then the start moves and the end stays`() {
        let moved = selection.movingStart(to: at(1_020), within: span)
        #expect(moved == ExportSelection(start: at(1_020), end: at(1_090)))
    }

    @Test func `given a start dragged past the end then it stops one second short of it`() {
        let moved = selection.movingStart(to: at(1_500), within: span)
        #expect(moved == ExportSelection(start: at(1_089), end: at(1_090)))
    }

    @Test func `given an end dragged past the start then it stops one second beyond it`() {
        let moved = selection.movingEnd(to: at(500), within: span)
        #expect(moved == ExportSelection(start: at(1_000), end: at(1_001)))
    }

    @Test func `given a start dragged before the history then it stops at the history`() {
        let moved = selection.movingStart(to: at(-500), within: span)
        #expect(moved == ExportSelection(start: at(0), end: at(1_090)))
    }

    @Test func `given an end dragged past the live edge then it stops there`() {
        let moved = selection.movingEnd(to: at(99_999), within: span)
        #expect(moved == ExportSelection(start: at(1_000), end: at(10_000)))
    }

    @Test func `given a fractional target then the boundary lands on a whole second`() {
        #expect(selection.movingStart(to: at(1_020.9), within: span).start == at(1_020))
        #expect(selection.movingEnd(to: at(1_200.9), within: span).end == at(1_200))
    }

    @Test func `given a boundary moved then the other one is never touched`() {
        #expect(selection.movingStart(to: at(1_020), within: span).end == selection.end)
        #expect(selection.movingEnd(to: at(1_200), within: span).start == selection.start)
    }
}

struct ExportSelectionRegionTests {

    private let span = TimeRange(start: at(1_000), end: at(2_000))
    private let selection = ExportSelection(start: at(1_400), end: at(1_490))

    @Test func `given the region moved then the duration is unchanged`() {
        let moved = selection.movingWholeRange(toStart: at(1_600), within: span)
        #expect(moved == ExportSelection(start: at(1_600), end: at(1_690)))
        #expect(moved.duration == selection.duration)
    }

    @Test func `given the region pushed past the live edge then it stops as a unit with its duration intact`() {
        let moved = selection.movingWholeRange(toStart: at(1_980), within: span)
        #expect(moved == ExportSelection(start: at(1_910), end: at(2_000)))
        #expect(moved.duration == selection.duration)
    }

    @Test func `given the region pushed before the history then it stops as a unit with its duration intact`() {
        let moved = selection.movingWholeRange(toStart: at(500), within: span)
        #expect(moved == ExportSelection(start: at(1_000), end: at(1_090)))
        #expect(moved.duration == selection.duration)
    }

    @Test func `given a region longer than the span then moving it clamps to the whole span`() {
        let tooLong = ExportSelection(start: at(1_000), end: at(2_000))
        #expect(tooLong.movingWholeRange(toStart: at(1_500), within: span) == tooLong)
    }
}

struct ExportSelectionRecordingTests {

    private let selection = ExportSelection(start: at(1_000), end: at(1_100))

    @Test func `given a selection clear of every gap then all of its seconds are recorded`() {
        #expect(selection.recordedSeconds(gaps: [gap(2_000, 2_500)]) == 100)
    }

    @Test func `given a selection spanning a gap then the gap's seconds are excluded`() {
        #expect(selection.recordedSeconds(gaps: [gap(1_020, 1_052)]) == 68)
    }

    @Test func `given a gap overhanging one edge then only the overlap is excluded`() {
        #expect(selection.recordedSeconds(gaps: [gap(900, 1_030)]) == 70)
    }

    @Test func `given a selection wholly inside a gap then it has no recording`() {
        #expect(selection.recordedSeconds(gaps: [gap(500, 2_000)]) == 0)
        #expect(!selection.hasRecording(gaps: [gap(500, 2_000)]))
    }

    @Test func `given overlapping gaps then their shared seconds are only excluded once`() {
        #expect(selection.recordedSeconds(gaps: [gap(1_000, 1_050), gap(1_020, 1_060)]) == 40)
    }

    @Test func `given any recorded second then the selection is valid`() {
        #expect(selection.hasRecording(gaps: [gap(1_000, 1_099)]))
    }
}

struct ExportSelectionClampStateTests {

    private let span = TimeRange(start: at(1_000), end: at(2_000))

    @Test func `given a start resting on the history then it reports that bound`() {
        let selection = ExportSelection(start: at(1_000), end: at(1_090))
        #expect(selection.isStartAtHistory(of: span))
        #expect(!selection.isEndAtLiveEdge(of: span))
    }

    @Test func `given an end resting on the live edge then it reports that bound`() {
        let selection = ExportSelection(start: at(1_900), end: at(2_000))
        #expect(selection.isEndAtLiveEdge(of: span))
        #expect(!selection.isStartAtHistory(of: span))
    }

    @Test func `given a one second selection then it reports the minimum`() {
        #expect(ExportSelection(start: at(1_400), end: at(1_401)).isAtMinimumLength)
        #expect(!ExportSelection(start: at(1_400), end: at(1_402)).isAtMinimumLength)
    }
}

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
private func span(_ start: TimeInterval, _ end: TimeInterval) -> TimeRange {
    TimeRange(start: at(start), end: at(end))
}
private func gap(_ start: TimeInterval, _ end: TimeInterval) -> FootageGap {
    FootageGap(range: TimeRange(start: at(start), end: at(end)))
}
