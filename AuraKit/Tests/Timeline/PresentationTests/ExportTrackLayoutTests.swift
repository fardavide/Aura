import Foundation
import SwiftUI
import Testing

import TimelineDomain
@testable import TimelinePresentation

/// Where the handles sit on the track, and who wins a touch that could belong to either. Pure
/// geometry, so the answers are assertions rather than something only a finger can discover.
struct ExportTrackLayoutTests {

    /// Minute density: one point per second, so a 90 s clip is 90 pt and the arithmetic is legible.
    private func layout(
        _ selection: ExportSelection,
        center: Date = at(1_045),
        length: CGFloat = 360
    ) -> ExportTrackLayout {
        ExportTrackLayout(
            axis: .horizontal,
            viewport: TimelineViewport(center: center, pointsPerHour: 3_600, length: length),
            thickness: 72,
            selection: selection
        )
    }

    @Test func `given a selection centred on the track then the bars sit either side of the middle`() {
        let sut = layout(ExportSelection(start: at(1_000), end: at(1_090)))
        #expect(sut.startPosition == 135)
        #expect(sut.endPosition == 225)
        #expect(sut.selectionLength == 90)
    }

    @Test func `given a knob then it sits flush outside the selection`() {
        let sut = layout(ExportSelection(start: at(1_000), end: at(1_090)))
        // 14pt wide, its inner edge against the 3pt bar's outer edge.
        #expect(sut.knobRect(.start).maxX == 135 - 1.5)
        #expect(sut.knobRect(.end).minX == 225 + 1.5)
        #expect(sut.knobRect(.start).width == 14)
        #expect(sut.knobRect(.start).height == 28)
    }

    @Test func `given a knob then it is vertically centred on the track`() {
        let sut = layout(ExportSelection(start: at(1_000), end: at(1_090)))
        #expect(sut.knobRect(.start).midY == 36)
    }

    @Test func `given a touch target then it is 44 wide and overhangs the track by 8 either side`() {
        let sut = layout(ExportSelection(start: at(1_000), end: at(1_090)))
        let target = sut.targetRect(.start)
        #expect(target.width == 44)
        #expect(target.midX == 135)
        #expect(target.minY == -8)
        #expect(target.maxY == 80)
    }

    @Test func `given a selection wide enough then the grab bar is drawn`() {
        #expect(layout(ExportSelection(start: at(1_000), end: at(1_044))).showsGrabBar)
        #expect(!layout(ExportSelection(start: at(1_000), end: at(1_043))).showsGrabBar)
    }

    /// The bars own 22 pt at each end, so a short clip keeps two reachable handles at the cost of
    /// its own interior — and at the minimum the interior is gone entirely rather than fighting
    /// the handles for the same pixels.
    @Test func `given a selection then the region drag keeps clear of both bars`() {
        let sut = layout(ExportSelection(start: at(1_000), end: at(1_090)))
        #expect(sut.regionDragRange == 157...203)
    }

    @Test func `given a selection at the one second minimum then there is no region to drag`() {
        #expect(layout(ExportSelection(start: at(1_045), end: at(1_046))).regionDragRange == nil)
    }

    @Test func `given a touch nearer one bar then that handle takes it`() {
        let sut = layout(ExportSelection(start: at(1_000), end: at(1_090)))
        #expect(sut.handle(closestTo: 140, lastMoved: .end) == .start)
        #expect(sut.handle(closestTo: 220, lastMoved: .start) == .end)
    }

    /// The only genuinely ambiguous case, and it has to be deterministic rather than whichever
    /// view happened to be on top.
    @Test func `given a touch exactly between the bars then the handle last moved keeps it`() {
        let sut = layout(ExportSelection(start: at(1_000), end: at(1_090)))
        #expect(sut.handle(closestTo: 180, lastMoved: .start) == .start)
        #expect(sut.handle(closestTo: 180, lastMoved: .end) == .end)
    }

    /// Newest at the top on the rail, so the later boundary is the one with the smaller coordinate.
    @Test func `given a vertical track then the end sits above the start`() {
        let sut = ExportTrackLayout(
            axis: .vertical,
            viewport: TimelineViewport(center: at(1_045), pointsPerHour: 3_600, length: 360),
            thickness: 50,
            selection: ExportSelection(start: at(1_000), end: at(1_090))
        )
        #expect(sut.startPosition == 225)
        #expect(sut.endPosition == 135)
        #expect(sut.selectionLength == 90)
    }
}

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
