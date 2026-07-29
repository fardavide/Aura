import Foundation
import Testing

import TimelineDomain
@testable import TimelinePresentation

struct TimelinePlayheadTests {

    @Test func `when advancing then the playhead moves by the elapsed time scaled by the speed`() {
        // given - when
        let step = TimelinePlayhead.advance(
            from: at(100),
            byRealSeconds: 2,
            at: .fourX,
            over: [],
            liveEdge: at(1000)
        )

        // then
        #expect(step == .moved(at(108)))
    }

    @Test func `given a gap ahead when advancing into it then the playhead clears the gap`() {
        // given
        let gaps = [gap(from: 110, to: 300)]

        // when
        let step = TimelinePlayhead.advance(from: at(100), byRealSeconds: 20, at: .oneX, over: gaps, liveEdge: at(1000))

        // then
        #expect(step == .moved(at(300)))
    }

    @Test func `given back to back gaps when advancing into the first then the playhead clears both`() {
        // given
        let gaps = [gap(from: 110, to: 300), gap(from: 300, to: 480)]

        // when
        let step = TimelinePlayhead.advance(from: at(100), byRealSeconds: 20, at: .oneX, over: gaps, liveEdge: at(1000))

        // then
        #expect(step == .moved(at(480)))
    }

    @Test func `given unordered gaps when advancing into the later one then the earlier one is not applied`() {
        // given
        let gaps = [gap(from: 500, to: 700), gap(from: 110, to: 300)]

        // when
        let step = TimelinePlayhead.advance(from: at(490), byRealSeconds: 20, at: .oneX, over: gaps, liveEdge: at(1000))

        // then
        #expect(step == .moved(at(700)))
    }

    @Test func `when advancing past the live edge then the playhead stops at it`() {
        // given - when
        let step = TimelinePlayhead.advance(from: at(900), byRealSeconds: 50, at: .eightX, over: [], liveEdge: at(1000))

        // then
        #expect(step == .reachedLiveEdge(at(1000)))
    }

    @Test func `given a gap running to the live edge when advancing into it then the playhead stops at the edge`() {
        // given
        let gaps = [gap(from: 910, to: 1000)]

        // when
        let step = TimelinePlayhead.advance(from: at(900), byRealSeconds: 20, at: .oneX, over: gaps, liveEdge: at(1000))

        // then
        #expect(step == .reachedLiveEdge(at(1000)))
    }
}

@MainActor
struct TimelineTransportTests {

    // MARK: - Play state

    @Test func `given a paused transport when toggling then it plays`() {
        // given
        let scenario = Scenario()

        // when
        scenario.sut.togglePlayPause()

        // then
        #expect(scenario.sut.isPlaying)
    }

    @Test func `given a playing transport when toggling then it pauses`() {
        // given
        let scenario = Scenario()
        scenario.sut.togglePlayPause()

        // when
        scenario.sut.togglePlayPause()

        // then
        #expect(!scenario.sut.isPlaying)
    }

    @Test func `given the playhead parked at the live edge when playing then it steps back onto footage`() {
        // given
        let scenario = Scenario(instant: at(1000))

        // when
        scenario.sut.togglePlayPause()

        // then
        #expect(scenario.clock.instant == at(940))
    }

    @Test func `given the playhead in history when playing then it stays where it was left`() {
        // given
        let scenario = Scenario(instant: at(400))

        // when
        scenario.sut.togglePlayPause()

        // then
        #expect(scenario.clock.instant == at(400))
    }

    // MARK: - Advancing

    @Test func `given a playing transport when advancing then the clock follows`() {
        // given
        let scenario = Scenario(instant: at(100))
        scenario.sut.togglePlayPause()

        // when
        scenario.sut.advance(byRealSeconds: 3)

        // then
        #expect(scenario.clock.instant == at(103))
    }

    @Test func `given a paused transport when advancing then the clock stays put`() {
        // given
        let scenario = Scenario(instant: at(100))

        // when
        scenario.sut.advance(byRealSeconds: 3)

        // then
        #expect(scenario.clock.instant == at(100))
    }

    @Test func `given a selected speed when advancing then the clock runs at it`() {
        // given
        let scenario = Scenario(instant: at(100))
        scenario.sut.togglePlayPause()

        // when
        scenario.sut.select(.eightX)
        scenario.sut.advance(byRealSeconds: 3)

        // then
        #expect(scenario.clock.instant == at(124))
    }

    @Test func `given a gap ahead when advancing into it then the clock clears the gap`() {
        // given
        let scenario = Scenario(instant: at(100), gaps: [gap(from: 110, to: 300)])
        scenario.sut.togglePlayPause()

        // when
        scenario.sut.advance(byRealSeconds: 20)

        // then
        #expect(scenario.clock.instant == at(300))
    }

    @Test func `given a playing transport when it reaches the live edge then playback stops there`() {
        // given
        let scenario = Scenario(instant: at(900))
        scenario.sut.togglePlayPause()

        // when
        scenario.sut.advance(byRealSeconds: 500)

        // then
        #expect(scenario.clock.instant == at(1000))
        #expect(!scenario.sut.isPlaying)
    }

    @Test func `given an extended span when advancing then the new live edge bounds playback`() {
        // given
        let scenario = Scenario(instant: at(900))
        scenario.sut.togglePlayPause()

        // when
        scenario.sut.update(gaps: [], span: TimeRange(start: at(0), end: at(2000)))
        scenario.sut.advance(byRealSeconds: 500)

        // then
        #expect(scenario.clock.instant == at(1400))
        #expect(scenario.sut.isPlaying)
    }

    // MARK: - Skipping

    @Test func `when skipping forward then the clock moves by the wall clock seconds`() {
        // given
        let scenario = Scenario(instant: at(100))

        // when
        scenario.sut.skip(by: 10)

        // then
        #expect(scenario.clock.instant == at(110))
    }

    @Test func `when skipping back past the start of the span then the clock clamps to it`() {
        // given
        let scenario = Scenario(instant: at(5))

        // when
        scenario.sut.skip(by: -10)

        // then
        #expect(scenario.clock.instant == at(0))
    }

    @Test func `when skipping past the live edge then the clock clamps to it`() {
        // given
        let scenario = Scenario(instant: at(995))

        // when
        scenario.sut.skip(by: 10)

        // then
        #expect(scenario.clock.instant == at(1000))
    }

    // MARK: - Yielding to the user

    @Test func `given a playing transport when the user takes the scrubber then playback pauses`() {
        // given
        let scenario = Scenario()
        scenario.sut.togglePlayPause()

        // when
        scenario.sut.beginInteraction()

        // then
        #expect(!scenario.sut.isPlaying)
    }

    @Test func `given a playing transport when the scrubber is released then playback resumes`() {
        // given
        let scenario = Scenario(instant: at(400))
        scenario.sut.togglePlayPause()
        scenario.sut.beginInteraction()

        // when
        scenario.sut.endInteraction()

        // then — the pause was the drag's, not the user's
        #expect(scenario.sut.isPlaying)
    }

    @Test func `given a paused transport when the scrubber is released then it stays paused`() {
        // given
        let scenario = Scenario(instant: at(400))
        scenario.sut.beginInteraction()

        // when
        scenario.sut.endInteraction()

        // then
        #expect(!scenario.sut.isPlaying)
    }

    @Test func `given repeated interaction phases then the resume intent survives them`() {
        // given — a scroll reports tracking, then interacting, then decelerating, each as a begin
        let scenario = Scenario(instant: at(400))
        scenario.sut.togglePlayPause()
        scenario.sut.beginInteraction()
        scenario.sut.beginInteraction()

        // when
        scenario.sut.endInteraction()

        // then
        #expect(scenario.sut.isPlaying)
    }

    @Test func `given a deliberate pause during an interaction then release does not resume`() {
        // given — navigation pauses the grid while a drag is still settling
        let scenario = Scenario(instant: at(400))
        scenario.sut.togglePlayPause()
        scenario.sut.beginInteraction()
        scenario.sut.pause()

        // when
        scenario.sut.endInteraction()

        // then
        #expect(!scenario.sut.isPlaying)
    }

    @Test func `given play toggled during an interaction then release respects the explicit intent`() {
        // given — the user pressed play and then pause mid-drag
        let scenario = Scenario(instant: at(400))
        scenario.sut.togglePlayPause()
        scenario.sut.beginInteraction()
        scenario.sut.togglePlayPause()
        scenario.sut.togglePlayPause()

        // when
        scenario.sut.endInteraction()

        // then
        #expect(!scenario.sut.isPlaying)
    }
}

@MainActor
private struct Scenario {
    let clock: ScrubClock
    let sut: TimelineTransport

    init(instant: Date = at(100), gaps: [FootageGap] = [], span: TimeRange = TimeRange(start: at(0), end: at(1000))) {
        clock = ScrubClock(instant: instant)
        sut = TimelineTransport(clock: clock, now: { at(1000) }, span: span)
        sut.update(gaps: gaps, span: span)
    }
}

private func gap(from start: TimeInterval, to end: TimeInterval) -> FootageGap {
    FootageGap(range: TimeRange(start: at(start), end: at(end)))
}

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
