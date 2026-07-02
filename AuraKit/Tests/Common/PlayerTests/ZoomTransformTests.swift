import CoreGraphics
import SwiftUI
import Testing

import CommonPlayer

struct ZoomTransformTests {

    private let viewport = CGSize(width: 400, height: 300)

    // MARK: Magnify

    @Test func `given an identity transform when magnifying by 2 at the center then scale is 2 and the offset stays zero`() {
        // given
        let sut = ZoomTransform.standard()

        // when
        let result = sut.magnified(by: 2, anchor: .center, viewport: viewport)

        // then
        #expect(result.scale == 2)
        #expect(result.offset == .zero)
    }

    @Test func `given an identity transform when magnifying beyond the maximum then the scale clamps to the maximum`() {
        // given
        let sut = ZoomTransform.standard()

        // when
        let result = sut.magnified(by: 10, anchor: .center, viewport: viewport)

        // then
        #expect(result.scale == 4)
        #expect(result.offset == .zero)
    }

    @Test func `given a zoomed and panned transform when magnifying below the minimum then it returns to identity`() {
        // given
        let sut = ZoomTransform.standard()
            .magnified(by: 2, anchor: .center, viewport: viewport)
            .panned(by: CGSize(width: 100, height: 50), viewport: viewport)

        // when
        let result = sut.magnified(by: 0.25, anchor: .center, viewport: viewport)

        // then
        #expect(result == ZoomTransform.standard())
    }

    @Test func `given an identity transform when magnifying by 2 at the top-leading anchor then the anchored corner stays fixed`() {
        // given
        let sut = ZoomTransform.standard()

        // when
        let result = sut.magnified(by: 2, anchor: .topLeading, viewport: viewport)

        // then
        #expect(result.scale == 2)
        #expect(result.offset == CGSize(width: 200, height: 150))
    }

    @Test func `given an edge-panned zoom when magnifying out then the offset re-clamps to the new content edge`() {
        // given: 4x zoom anchored at the top-leading corner sits exactly at the pan bound (600, 450)
        let sut = ZoomTransform.standard()
            .magnified(by: 4, anchor: .topLeading, viewport: viewport)

        // when
        let result = sut.magnified(by: 0.5, anchor: .center, viewport: viewport)

        // then
        #expect(result.scale == 2)
        #expect(result.offset == CGSize(width: 200, height: 150))
    }

    // MARK: Pan

    @Test func `given a 2x zoom when panning within bounds then the offset moves by the translation`() {
        // given
        let sut = ZoomTransform.standard()
            .magnified(by: 2, anchor: .center, viewport: viewport)

        // when
        let result = sut.panned(by: CGSize(width: 50, height: -30), viewport: viewport)

        // then
        #expect(result.offset == CGSize(width: 50, height: -30))
    }

    @Test func `given a 2x zoom when panning past the edge then the offset clamps at the content edge`() {
        // given
        let sut = ZoomTransform.standard()
            .magnified(by: 2, anchor: .center, viewport: viewport)

        // when
        let result = sut.panned(by: CGSize(width: 500, height: -500), viewport: viewport)

        // then
        #expect(result.offset == CGSize(width: 200, height: -150))
    }

    @Test func `given an identity transform when panning then the offset stays zero`() {
        // given
        let sut = ZoomTransform.standard()

        // when
        let result = sut.panned(by: CGSize(width: 50, height: 50), viewport: viewport)

        // then
        #expect(result == ZoomTransform.standard())
    }

    // MARK: Toggle + reset

    @Test func `given an identity transform when toggling zoom at a point then it zooms to 2x anchored at that point`() {
        // given
        let sut = ZoomTransform.standard()

        // when
        let result = sut.togglingZoom(at: UnitPoint(x: 0.25, y: 0.5), viewport: viewport)

        // then
        #expect(result.scale == 2)
        #expect(result.offset == CGSize(width: 100, height: 0))
    }

    @Test func `given a zoomed and panned transform when toggling zoom then it returns to identity`() {
        // given
        let sut = ZoomTransform.standard()
            .magnified(by: 3, anchor: .center, viewport: viewport)
            .panned(by: CGSize(width: 120, height: -80), viewport: viewport)

        // when
        let result = sut.togglingZoom(at: .center, viewport: viewport)

        // then
        #expect(result == ZoomTransform.standard())
    }

    @Test func `given a zoomed and panned transform when reset then it returns to identity`() {
        // given
        let sut = ZoomTransform.standard()
            .magnified(by: 3, anchor: .center, viewport: viewport)
            .panned(by: CGSize(width: 120, height: -80), viewport: viewport)

        // when
        let result = sut.reset()

        // then
        #expect(result == ZoomTransform.standard())
    }

    // MARK: isZoomed

    @Test func `given an identity transform then it is not zoomed`() {
        #expect(ZoomTransform.standard().isZoomed == false)
    }

    @Test func `given a magnified transform then it is zoomed`() {
        // given
        let sut = ZoomTransform.standard()
            .magnified(by: 2, anchor: .center, viewport: viewport)

        // then
        #expect(sut.isZoomed)
    }
}
