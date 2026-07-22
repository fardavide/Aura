import CoreGraphics
import Testing

@testable import TimelinePresentation

struct TimelineGridLayoutTests {

    @Test func `given one camera in a wide short viewport when fitting then the tile is height limited`() {
        // given - when
        let layout = TimelineGridLayout.bestFit(
            tileCount: 1,
            available: CGSize(width: 2000, height: 450),
            spacing: 12,
            minimumTileWidth: 220
        )

        // then — 450pt of height allows a 16:9 tile 800pt wide, well under the 2000pt of width
        #expect(layout == TimelineGridLayout(columnCount: 1, tileWidth: 800))
    }

    @Test func `given three cameras in a desktop viewport when fitting then two columns maximise the tile`() {
        // given - when
        let layout = TimelineGridLayout.bestFit(
            tileCount: 3,
            available: CGSize(width: 1968, height: 1000),
            spacing: 12,
            minimumTileWidth: 220
        )

        // then — 1 column is height-bound at 578pt, 3 columns width-bound at 648pt; 2 columns win at 878pt
        #expect(layout == TimelineGridLayout(columnCount: 2, tileWidth: 878))
    }

    @Test func `given more cameras than fit when fitting then it falls back to a scrolling grid of minimum width tiles`() {
        // given - when
        let layout = TimelineGridLayout.bestFit(
            tileCount: 12,
            available: CGSize(width: 700, height: 400),
            spacing: 10,
            minimumTileWidth: 220
        )

        // then — no arrangement fits 12 tiles at ≥220pt, so 3 minimum-width columns share the width and scroll
        #expect(layout == TimelineGridLayout(columnCount: 3, tileWidth: 226))
    }

    @Test func `given fewer cameras than fallback columns when fitting then the columns clamp to the camera count`() {
        // given - when
        let layout = TimelineGridLayout.bestFit(
            tileCount: 2,
            available: CGSize(width: 2000, height: 10),
            spacing: 12,
            minimumTileWidth: 220
        )

        // then — 10pt of height fits nothing, and the width-based fallback of 8 columns clamps to the 2 tiles
        #expect(layout == TimelineGridLayout(columnCount: 2, tileWidth: 994))
    }

    @Test func `given no cameras when fitting then a single full width column is returned`() {
        // given - when
        let layout = TimelineGridLayout.bestFit(
            tileCount: 0,
            available: CGSize(width: 700, height: 400),
            spacing: 10,
            minimumTileWidth: 220
        )

        // then
        #expect(layout == TimelineGridLayout(columnCount: 1, tileWidth: 700))
    }
}
