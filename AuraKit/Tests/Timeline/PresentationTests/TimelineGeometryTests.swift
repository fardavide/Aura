import Foundation
import SwiftUI
import Testing

import TimelineDomain
@testable import TimelinePresentation

struct TimelineViewportTests {

    @Test func `given a density and length then the visible window is centred on the playhead`() {
        // given — 600pt at 120pt/h shows 5 hours
        let viewport = TimelineViewport(center: at(43_200), pointsPerHour: 120, length: 600)

        // then
        #expect(viewport.visible.start == at(43_200 - 9_000))
        #expect(viewport.visible.end == at(43_200 + 9_000))
    }

    @Test func `given an instant when mapping to a position then the centre sits at the middle`() {
        // given
        let viewport = TimelineViewport(center: at(43_200), pointsPerHour: 120, length: 600)

        // then
        #expect(viewport.position(of: at(43_200)) == 300)
        #expect(viewport.position(of: viewport.visible.start) == 0)
        #expect(viewport.position(of: viewport.visible.end) == 600)
    }

    @Test func `given a position when mapping to an instant then it inverts the position mapping`() {
        // given
        let viewport = TimelineViewport(center: at(43_200), pointsPerHour: 120, length: 600)

        // then — positions outside the track still read as instants, so a drag can run past the edge
        #expect(viewport.instant(atPosition: 300) == at(43_200))
        #expect(viewport.instant(atPosition: 0) == viewport.visible.start)
        #expect(viewport.instant(atPosition: 900) == at(43_200 + 18_000))
    }

    @Test func `given a shift in points then the centre moves by that much footage`() {
        // given — at 120pt/h one point is 30 seconds
        let viewport = TimelineViewport(center: at(43_200), pointsPerHour: 120, length: 600)

        // then
        #expect(viewport.center(shiftedByPoints: 10) == at(43_500))
        #expect(viewport.center(shiftedByPoints: -10) == at(42_900))
    }

    @Test func `given a zoomed-in density then the same length shows less time`() {
        // given
        let wide = TimelineViewport(center: at(43_200), pointsPerHour: 36, length: 600)
        let tight = TimelineViewport(center: at(43_200), pointsPerHour: 480, length: 600)

        // then
        #expect(wide.visible.end.timeIntervalSince(wide.visible.start) == 60_000)
        #expect(tight.visible.end.timeIntervalSince(tight.visible.start) == 4_500)
    }

    @Test func `given a zero length or density then the window collapses onto the centre`() {
        // given — a first layout pass measures nothing; the maths must not divide by zero
        #expect(TimelineViewport(center: at(100), pointsPerHour: 120, length: 0).visible.start == at(100))
        #expect(TimelineViewport(center: at(100), pointsPerHour: 0, length: 600).visible.end == at(100))
        #expect(TimelineViewport(center: at(100), pointsPerHour: 0, length: 600).center(shiftedByPoints: 50) == at(100))
    }
}

struct DayOverviewTests {

    @Test func `given motion buckets when rolling up then each hour averages its buckets`() {
        // given — hour 0 holds 20 and 40, hour 2 holds 90
        let timeline = DayTimeline(
            markers: [],
            motion: [
                MotionBucket(time: at(0), intensity: 20),
                MotionBucket(time: at(1_800), intensity: 40),
                MotionBucket(time: at(7_200), intensity: 90),
            ],
            gaps: []
        )

        // when
        let overview = DayOverview.rolledUp(from: timeline, day: day, calendar: utc)

        // then
        #expect(overview.hourlyMotion.count == 24)
        #expect(overview.hourlyMotion[0] == 30)
        #expect(overview.hourlyMotion[1] == 0)
        #expect(overview.hourlyMotion[2] == 90)
    }

    @Test func `given buckets outside the day when rolling up then they are ignored`() {
        // given
        let timeline = DayTimeline(
            markers: [],
            motion: [MotionBucket(time: at(-3_600), intensity: 100), MotionBucket(time: at(90_000), intensity: 100)],
            gaps: []
        )

        // when
        let overview = DayOverview.rolledUp(from: timeline, day: day, calendar: utc)

        // then
        #expect(overview.hourlyMotion.allSatisfy { $0 == 0 })
    }

    @Test func `given markers when rolling up then the day's are kept at every severity`() {
        // given
        let timeline = DayTimeline(
            markers: [
                ReviewMarker(start: at(3_600), end: at(3_660), severity: .alert),
                ReviewMarker(start: at(7_200), end: at(7_260), severity: .detection),
                ReviewMarker(start: at(90_000), end: nil, severity: .alert),
            ],
            motion: [],
            gaps: []
        )

        // when
        let overview = DayOverview.rolledUp(from: timeline, day: day, calendar: utc)

        // then — detections included, so the bar speaks the same severity vocabulary as the tracks
        #expect(overview.markers == [
            ReviewMarker(start: at(3_600), end: at(3_660), severity: .alert),
            ReviewMarker(start: at(7_200), end: at(7_260), severity: .detection),
        ])
    }

    @Test func `given a gap crossing midnight when rolling up then it is clipped to the day`() {
        // given
        let timeline = DayTimeline(
            markers: [],
            motion: [],
            gaps: [FootageGap(range: TimeRange(start: at(-1_800), end: at(1_800)))]
        )

        // when
        let overview = DayOverview.rolledUp(from: timeline, day: day, calendar: utc)

        // then
        #expect(overview.gaps == [TimeRange(start: at(0), end: at(1_800))])
    }

    @Test func `given a gap outside the day when rolling up then it is dropped`() {
        // given
        let timeline = DayTimeline(
            markers: [],
            motion: [],
            gaps: [FootageGap(range: TimeRange(start: at(90_000), end: at(93_600)))]
        )

        // then
        #expect(DayOverview.rolledUp(from: timeline, day: day, calendar: utc).gaps.isEmpty)
    }
}

struct TimelineRulerTicksTests {

    @Test func `given the hour zoom then ticks land every ten minutes`() {
        // given — 480pt/h over 600pt shows 75 minutes
        let viewport = TimelineViewport(center: at(43_200), pointsPerHour: 480, length: 600)

        // when
        let ticks = TimelineRulerTicks.ticks(in: viewport, zoom: .hour, calendar: utc, edgeInset: 0)

        // then
        let gaps = zip(ticks, ticks.dropFirst()).map { $1.instant.timeIntervalSince($0.instant) }
        #expect(!ticks.isEmpty)
        #expect(gaps.allSatisfy { $0 == 600 })
    }

    @Test func `given the day and week zooms then the tick step widens`() {
        // given
        let day = TimelineViewport(center: at(43_200), pointsPerHour: 120, length: 600)
        let week = TimelineViewport(center: at(43_200), pointsPerHour: 36, length: 600)

        // when
        let dayTicks = TimelineRulerTicks.ticks(in: day, zoom: .day, calendar: utc, edgeInset: 0)
        let weekTicks = TimelineRulerTicks.ticks(in: week, zoom: .week, calendar: utc, edgeInset: 0)

        // then
        #expect(dayTicks[1].instant.timeIntervalSince(dayTicks[0].instant) == 1_800)
        #expect(weekTicks[1].instant.timeIntervalSince(weekTicks[0].instant) == 10_800)
    }

    @Test func `given ticks near the edges then they are dropped so labels never clip`() {
        // given
        let viewport = TimelineViewport(center: at(43_200), pointsPerHour: 120, length: 600)

        // when
        let ticks = TimelineRulerTicks.ticks(in: viewport, zoom: .day, calendar: utc, edgeInset: 60)

        // then
        #expect(ticks.allSatisfy { $0.position >= 60 && $0.position <= 540 })
    }

    @Test func `given midnight in view then that tick is marked as a day boundary`() {
        // given — centred on midnight
        let viewport = TimelineViewport(center: at(86_400), pointsPerHour: 120, length: 600)

        // when
        let ticks = TimelineRulerTicks.ticks(in: viewport, zoom: .day, calendar: utc, edgeInset: 0)

        // then
        #expect(ticks.filter(\.isDayBoundary).map(\.instant) == [at(86_400)])
    }

    @Test func `given a collapsed viewport then there are no ticks`() {
        let viewport = TimelineViewport(center: at(43_200), pointsPerHour: 120, length: 0)
        #expect(TimelineRulerTicks.ticks(in: viewport, zoom: .day, calendar: utc, edgeInset: 0).isEmpty)
    }
}

struct MarkerNavigatorTests {

    private let markers = [
        ReviewMarker(start: at(100), end: at(160), severity: .detection),
        ReviewMarker(start: at(300), end: at(360), severity: .alert),
        ReviewMarker(start: at(500), end: nil, severity: .alert),
    ]

    @Test func `given an instant between markers when stepping forward then the next one is found`() {
        #expect(MarkerNavigator.marker(after: at(200), in: markers)?.start == at(300))
    }

    @Test func `given an instant exactly on a marker when stepping forward then it advances past it`() {
        #expect(MarkerNavigator.marker(after: at(300), in: markers)?.start == at(500))
    }

    @Test func `given the last marker when stepping forward then there is none`() {
        #expect(MarkerNavigator.marker(after: at(500), in: markers) == nil)
    }

    @Test func `given an instant between markers when stepping back then the previous one is found`() {
        #expect(MarkerNavigator.marker(before: at(200), in: markers)?.start == at(100))
    }

    @Test func `given an instant exactly on a marker when stepping back then it moves off it`() {
        #expect(MarkerNavigator.marker(before: at(300), in: markers)?.start == at(100))
    }

    @Test func `given the first marker when stepping back then there is none`() {
        #expect(MarkerNavigator.marker(before: at(100), in: markers) == nil)
    }

    @Test func `given unsorted markers when stepping then order is not assumed`() {
        let shuffled = [markers[2], markers[0], markers[1]]
        #expect(MarkerNavigator.marker(after: at(200), in: shuffled)?.start == at(300))
        #expect(MarkerNavigator.marker(before: at(400), in: shuffled)?.start == at(300))
    }

    @Test func `given an instant inside a marker then it is the active one`() {
        #expect(MarkerNavigator.marker(at: at(320), in: markers)?.severity == .alert)
        #expect(MarkerNavigator.marker(at: at(360), in: markers) == nil)
    }

    @Test func `given an in-progress marker then it stays active past its start`() {
        #expect(MarkerNavigator.marker(at: at(100_000), in: markers)?.start == at(500))
    }
}

private let day = TimeRange(start: at(0), end: at(86_400))
private let utc = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()
private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
