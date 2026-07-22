import Foundation
import SwiftUI
import Testing

import TimelineDomain
@testable import TimelinePresentation

struct TimelineScaleTests {

    @Test func `given a horizontal scale when mapping offsets then instants run start to end`() {
        // given
        let scale = TimelineScale(axis: .horizontal, span: day, pointsPerHour: 120, viewport: 600)

        // then — 24h at 120pt/h is a 2880pt track
        #expect(scale.contentLength == 2880)
        #expect(scale.instant(atOffset: 0) == at(0))
        #expect(scale.instant(atOffset: 1440) == at(43_200))
        #expect(scale.instant(atOffset: 2880) == at(86_400))
    }

    @Test func `given a vertical scale when mapping offsets then instants run end back to start`() {
        // given
        let scale = TimelineScale(axis: .vertical, span: day, pointsPerHour: 120, viewport: 600)

        // then — the live edge sits at the top, the past below it
        #expect(scale.instant(atOffset: 0) == at(86_400))
        #expect(scale.instant(atOffset: 2880) == at(0))
    }

    @Test func `given an instant when mapping to an offset then it inverts the offset mapping`() {
        // given
        let horizontal = TimelineScale(axis: .horizontal, span: day, pointsPerHour: 120, viewport: 600)
        let vertical = TimelineScale(axis: .vertical, span: day, pointsPerHour: 120, viewport: 600)

        // then
        #expect(horizontal.offset(for: at(43_200)) == 1440)
        #expect(horizontal.offset(for: at(0)) == 0)
        #expect(vertical.offset(for: at(86_400)) == 0)
        #expect(vertical.offset(for: at(43_200)) == 1440)
    }

    @Test func `given an offset outside the track when mapping then the instant clamps to the span`() {
        // given
        let scale = TimelineScale(axis: .horizontal, span: day, pointsPerHour: 120, viewport: 600)

        // then
        #expect(scale.instant(atOffset: -50) == at(0))
        #expect(scale.instant(atOffset: 3000) == at(86_400))
    }

    @Test func `given a sparse span when measuring then the content never shrinks below the viewport`() {
        // given
        let twoHours = TimeRange(start: at(0), end: at(7_200))
        let scale = TimelineScale(axis: .horizontal, span: twoHours, pointsPerHour: 36, viewport: 600)

        // then — 72pt of track stretches to the 600pt viewport, and offsets map across it
        #expect(scale.contentLength == 600)
        #expect(scale.instant(atOffset: 300) == at(3_600))
    }
}

struct TimelineZoomTests {

    @Test func `given a preset density when snapping then that preset is chosen`() {
        #expect(TimelineZoom.nearest(to: 36) == .week)
        #expect(TimelineZoom.nearest(to: 120) == .day)
        #expect(TimelineZoom.nearest(to: 480) == .hour)
    }

    @Test func `given a density between presets when snapping then the geometrically nearer preset wins`() {
        // then — the day/hour midpoint is √(120·480) = 240; the week/day midpoint is √(36·120) ≈ 65.7
        #expect(TimelineZoom.nearest(to: 239) == .day)
        #expect(TimelineZoom.nearest(to: 241) == .hour)
        #expect(TimelineZoom.nearest(to: 65) == .week)
        #expect(TimelineZoom.nearest(to: 66) == .day)
    }

    @Test func `given a density outside the presets when clamping then it stays within the zoom range`() {
        #expect(TimelineZoom.clamped(10_000) == TimelineZoom.hour.pointsPerHour)
        #expect(TimelineZoom.clamped(1) == TimelineZoom.week.pointsPerHour)
        #expect(TimelineZoom.clamped(200) == 200)
    }

    @Test func `given a preset when cycling then next visits every preset and wraps`() {
        #expect(TimelineZoom.hour.next == .day)
        #expect(TimelineZoom.day.next == .week)
        #expect(TimelineZoom.week.next == .hour)
    }
}

private let day = TimeRange(start: at(0), end: at(86_400))
private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
