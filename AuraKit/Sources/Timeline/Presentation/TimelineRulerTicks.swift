import Foundation
import SwiftUI

/// One labelled tick under the scrub track.
struct TimelineRulerTick: Equatable, Identifiable {
    let instant: Date
    let position: CGFloat
    /// Midnight — labelled with the weekday rather than a time, so a multi-day window reads.
    let isDayBoundary: Bool

    var id: Date { instant }
}

/// Where the ruler's labels fall for a given viewport. Ticks are anchored to the **calendar day**,
/// not to the epoch: a half-hour UTC offset would otherwise put every 3-hour label on the half hour.
enum TimelineRulerTicks {

    static func ticks(
        in viewport: TimelineViewport,
        zoom: TimelineZoom,
        calendar: Calendar,
        edgeInset: CGFloat
    ) -> [TimelineRulerTick] {
        guard viewport.length > 0, viewport.pointsPerHour > 0 else { return [] }
        let visible = viewport.visible
        let step = zoom.rulerStep
        let anchor = calendar.startOfDay(for: visible.start)
        let stepsToFirst = (visible.start.timeIntervalSince(anchor) / step).rounded(.up)

        var ticks: [TimelineRulerTick] = []
        var instant = anchor.addingTimeInterval(stepsToFirst * step)
        while instant < visible.end {
            let position = viewport.position(of: instant)
            if position >= edgeInset, position <= viewport.length - edgeInset {
                ticks.append(
                    TimelineRulerTick(
                        instant: instant,
                        position: position,
                        isDayBoundary: calendar.startOfDay(for: instant) == instant
                    )
                )
            }
            instant = instant.addingTimeInterval(step)
        }
        return ticks
    }
}

private extension TimelineZoom {
    /// How far apart the labels sit, chosen per density so they stay ~60–110pt apart.
    var rulerStep: TimeInterval {
        switch self {
        case .hour: 600
        case .day: 1_800
        case .week: 10_800
        }
    }
}
