import SwiftUI
import Testing

@testable import TimelinePresentation

/// The pure geometry behind the 45° hatch — unit-testable without a `GraphicsContext` (tokens
/// §2.16).
struct TimelineHatchTests {

    @Test func `given a band when computing hatch segments then each one runs at forty five degrees`() {
        // given — a square band, so a 45° run has equal width and height
        let rect = CGRect(x: 0, y: 0, width: 20, height: 20)

        // when
        let segments = TimelineHatch.lineSegments(in: rect)

        // then — every segment's run equals the rect's height (the 45° slope), and each stays
        // inside the rect's vertical extent
        #expect(!segments.isEmpty)
        for (start, end) in segments {
            #expect(abs(end.x - start.x) == rect.height)
            #expect(start.y == rect.maxY)
            #expect(end.y == rect.minY)
        }
    }

    @Test func `given a band when computing hatch segments then consecutive origins are one pitch apart`() {
        // given
        let rect = CGRect(x: 0, y: 0, width: 40, height: 10)

        // when
        let origins = TimelineHatch.lineSegments(in: rect).map(\.0.x)

        // then
        #expect(origins.count > 1)
        for (a, b) in zip(origins, origins.dropFirst()) {
            #expect(b - a == 7)
        }
    }

    @Test func `given a band when computing hatch segments then they cover it from before its leading edge to its trailing edge`() throws {
        // given
        let rect = CGRect(x: 10, y: 0, width: 30, height: 12)

        // when
        let origins = TimelineHatch.lineSegments(in: rect).map(\.0.x)
        let first = try #require(origins.first)
        let last = try #require(origins.last)

        // then — the run starts a full band-height before the leading edge (so the first diagonal
        // still crosses the corner) and stops before the trailing edge
        #expect(first == rect.minX - rect.height)
        #expect(last < rect.maxX)
    }
}
