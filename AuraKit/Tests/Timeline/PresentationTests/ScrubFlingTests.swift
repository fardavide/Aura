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

    @Test(arguments: [CGFloat(-125), CGFloat(125)])
    func `given a small movement at release then the scrub settles without gliding`(velocity: CGFloat) {
        // given - when
        let fling = ScrubFling(velocity: velocity)

        // then
        #expect(fling == nil)
    }

    @Test func `given a brisk release then the glide travels a short distance before settling`() throws {
        // given
        let fling = try #require(ScrubFling(velocity: 1000))

        // when
        let total = fling.offset(at: fling.duration)

        // then
        #expect((90...115).contains(total))
    }

    @Test func `given time passing then the glide never reverses`() throws {
        // given
        let fling = try #require(ScrubFling(velocity: -800))

        // when
        let offsets = stride(from: 0.0, through: 2.0, by: 0.1).map(fling.offset(at:))

        // then — a backwards release glides monotonically backwards
        #expect(offsets == offsets.sorted(by: >))
    }

    @Test func `given a brisk release when the glide reaches its end then the track is nearly stationary`() throws {
        // given
        let fling = try #require(ScrubFling(velocity: 1000))

        // when
        let finalMovement = fling.offset(at: fling.duration) - fling.offset(at: fling.duration - 0.001)

        // then
        #expect(abs(finalMovement) < 0.01)
    }

    @Test func `given a harder release then the glide lasts longer`() throws {
        // given
        let brisk = try #require(ScrubFling(velocity: 2000))
        let soft = try #require(ScrubFling(velocity: 200))

        // then
        #expect(brisk.duration > soft.duration)
    }
}
