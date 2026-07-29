import Foundation
import Testing

import TimelineDomain
@testable import TimelinePresentation

struct FilmstripSlotsTests {

    @Test
    func `when the visible range spans half an hour then slots align to the ten minute grid`() {
        // given
        let visible = TimeRange(start: at(1000), end: at(2800))
        let span = TimeRange(start: at(0), end: at(100_000))

        // when
        let slots = FilmstripSlots.instants(visible: visible, span: span)

        // then
        #expect(slots == [at(600), at(1200), at(1800), at(2400)])
    }
    @Test
    func `given a span starting mid grid when slots are computed then slots wholly before it are excluded`() {
        // given
        let visible = TimeRange(start: at(0), end: at(3000))
        let span = TimeRange(start: at(1250), end: at(100_000))

        // when
        let slots = FilmstripSlots.instants(visible: visible, span: span)

        // then — the slot ending exactly at 1200 holds no footage; the one straddling 1250 does
        #expect(slots == [at(1200), at(1800), at(2400)])
    }
    @Test
    func `given a span ending mid grid when slots are computed then slots at or after the live edge are excluded`() {
        // given
        let visible = TimeRange(start: at(0), end: at(3000))
        let span = TimeRange(start: at(0), end: at(1300))

        // when
        let slots = FilmstripSlots.instants(visible: visible, span: span)

        // then — the slot starting at 1200 straddles the live edge; the one at 1800 is future
        #expect(slots == [at(0), at(600), at(1200)])
    }
}

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
