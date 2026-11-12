#if os(iOS)
import SwiftUI
import Testing
import UIKit

import TimelineDomain

@testable import TimelinePresentation

@MainActor
struct TimelineScrollDecelerationTests {
    @Test(arguments: [TimelineCardArrangement.stack, .rail])
    func `when the Timeline tab lays out its histogram then the native scroll view uses fast deceleration`(
        arrangement: TimelineCardArrangement
    ) throws {
        // given
        let scenario = Scenario(arrangement: arrangement)
        defer {
            scenario.window.isHidden = true
            scenario.window.rootViewController = nil
        }

        // when
        scenario.host.view.layoutIfNeeded()

        // then
        let scrollView = try #require(scenario.scrollView(in: scenario.host.view))
        #expect(scrollView.decelerationRate == .fast)
    }

    @Test(arguments: [Axis.Set.horizontal, .vertical])
    func `given a brisk release when settling the histogram then the target coasts farther along the scroll axis`(
        axes: Axis.Set
    ) {
        // given
        let behavior = TimelineScrollTargetBehavior()
        let origin = CGPoint(x: 200, y: 200)

        // when
        let target = behavior.extendedOrigin(origin, velocity: CGVector(dx: 1_000, dy: -1_000), axes: axes)

        // then
        let expected = axes == .horizontal ? CGPoint(x: 225, y: 200) : CGPoint(x: 200, y: 175)
        #expect(target == expected)
    }

    @MainActor private struct Scenario {
        let host: UIHostingController<ScrollableTimelineView>
        let window: UIWindow

        init(arrangement: TimelineCardArrangement) {
            let end = Date(timeIntervalSince1970: 100_000)
            let span = TimeRange(start: end.addingTimeInterval(-86_400), end: end)
            let clock = ScrubClock(instant: end)
            host = UIHostingController(rootView: ScrollableTimelineView(
                arrangement: arrangement,
                span: span,
                timeline: DayTimeline(markers: [], motion: [], gaps: []),
                clock: clock,
                transport: TimelineTransport(clock: clock, now: { end }, span: span),
                onScrub: { clock.scrub(to: $0) }
            ))
            let size = arrangement.axis == .horizontal
                ? CGSize(width: 402, height: 874)
                : CGSize(width: 874, height: 402)
            window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = host
            window.isHidden = false
        }

        func scrollView(in view: UIView) -> UIScrollView? {
            if let scrollView = view as? UIScrollView { return scrollView }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
    }
}
#endif
