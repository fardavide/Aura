import Foundation
import SwiftUI

import TimelineDomain

/// Maps between the histogram's scroll offset and the instant under its fixed centre playhead, at
/// a given zoom density. Horizontal runs start→end, left→right; vertical runs end→start, top→
/// bottom (the live edge on top, so scrolling up reveals older footage).
struct TimelineScale: Equatable {
    let axis: Axis
    let span: TimeRange
    let pointsPerHour: CGFloat
    let viewport: CGFloat

    /// The track's length along the scroll axis — never shorter than the viewport, so a sparse
    /// span still fills the card.
    var contentLength: CGFloat {
        max(viewport, CGFloat(span.end.timeIntervalSince(span.start) / 3600) * pointsPerHour)
    }

    func instant(atOffset offset: CGFloat) -> Date {
        guard contentLength > 0 else { return span.end }
        let fraction = min(1, max(0, offset / contentLength))
        let duration = span.end.timeIntervalSince(span.start)
        return axis == .vertical
            ? span.end.addingTimeInterval(-duration * Double(fraction))
            : span.start.addingTimeInterval(duration * Double(fraction))
    }

    func offset(for instant: Date) -> CGFloat {
        let duration = span.end.timeIntervalSince(span.start)
        guard duration > 0 else { return 0 }
        let fraction = axis == .vertical
            ? span.end.timeIntervalSince(instant) / duration
            : instant.timeIntervalSince(span.start) / duration
        return CGFloat(min(1, max(0, fraction))) * contentLength
    }
}
