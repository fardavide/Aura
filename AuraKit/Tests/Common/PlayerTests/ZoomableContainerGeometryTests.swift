import SwiftUI
import Testing

@testable import CommonPlayer

/// `contentRect(in:)` is what every gesture anchor computes against — a pinch's `UnitPoint` must be
/// relative to where `content` actually sits, not the (possibly much bigger) container it's boxed
/// inside of. See `ZoomableContainer.contentSize`'s own doc comment for the reported symptoms a
/// wrong rect here produces.
@MainActor
struct ZoomableContainerGeometryTests {

    private let arena = CGSize(width: 400, height: 900)

    @Test func `given no content size when reading the content rect then it fills the arena`() {
        // given
        let sut = ZoomableContainer(onSingleTap: {}, clipsContent: true, contentSize: nil) { Color.clear }

        // when
        let rect = sut.contentRect(in: arena)

        // then
        #expect(rect == CGRect(origin: .zero, size: arena))
    }

    @Test func `given a centered content size when reading the content rect then it centers in the arena`() {
        // given
        let contentSize = CGSize(width: 400, height: 225)
        let sut = ZoomableContainer(onSingleTap: {}, clipsContent: true, alignment: .center, contentSize: contentSize) {
            Color.clear
        }

        // when
        let rect = sut.contentRect(in: arena)

        // then
        #expect(rect == CGRect(x: 0, y: 337.5, width: 400, height: 225))
    }

    @Test func `given a top-aligned content size when reading the content rect then it sits flush to the top`() {
        // given
        let contentSize = CGSize(width: 400, height: 225)
        let sut = ZoomableContainer(onSingleTap: {}, clipsContent: true, alignment: .top, contentSize: contentSize) {
            Color.clear
        }

        // when
        let rect = sut.contentRect(in: arena)

        // then
        #expect(rect == CGRect(x: 0, y: 0, width: 400, height: 225))
    }

    @Test func `given a top-aligned content size with a rest offset when reading the content rect then the offset shifts it`() {
        // given
        let contentSize = CGSize(width: 400, height: 225)
        let sut = ZoomableContainer(
            onSingleTap: {},
            clipsContent: true,
            alignment: .top,
            contentSize: contentSize,
            restOffset: CGSize(width: 0, height: 60)
        ) {
            Color.clear
        }

        // when
        let rect = sut.contentRect(in: arena)

        // then
        #expect(rect == CGRect(x: 0, y: 60, width: 400, height: 225))
    }
}
