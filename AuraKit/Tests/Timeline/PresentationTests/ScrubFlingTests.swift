import Foundation
import Testing

@testable import TimelinePresentation

struct ScrubFlingTests {

    @Test func `given a gentle release then no fling starts`() {
        // given - when
        let fling = ScrubFling(velocity: 40)

        // then
        #expect(fling == nil)
    }

    @Test func `given a brisk release then the glide covers the projected distance`() throws {
        // given
        let fling = try #require(ScrubFling(velocity: 1000))

        // when
        let total = fling.offset(at: fling.duration)

        // then — the deceleration curve integrates to roughly half a second of travel at the
        // release speed, minus the tail cut off under the rest velocity
        #expect(abs(total - 495.6) < 1)
    }

    @Test func `given time passing then the glide never reverses`() throws {
        // given
        let fling = try #require(ScrubFling(velocity: -800))

        // when
        let offsets = stride(from: 0.0, through: 2.0, by: 0.1).map(fling.offset(at:))

        // then — a backwards release glides monotonically backwards
        #expect(offsets == offsets.sorted(by: >))
    }

    @Test func `given a harder release then the glide lasts longer`() throws {
        // given
        let brisk = try #require(ScrubFling(velocity: 2000))
        let soft = try #require(ScrubFling(velocity: 200))

        // then
        #expect(brisk.duration > soft.duration)
    }
}
