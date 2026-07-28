import Foundation
import SwiftUI

import TimelineDomain

/// The window of time a centre-anchored track shows: the playhead is fixed at the middle and the
/// footage slides under it, so the geometry is a function of the playhead instant rather than of a
/// scroll offset (`TimelineScale`, which the Timeline tab's `ScrollView` uses, models the other one).
///
/// Positions run **forward in time from the leading edge**. A vertical track — newest at the top —
/// mirrors them itself; keeping one direction here means one place to reason about the maths.
struct TimelineViewport: Equatable {
    let center: Date
    let pointsPerHour: CGFloat
    /// The track's extent along the time axis, in points.
    let length: CGFloat

    /// The footage the track currently shows. Collapses onto the centre before the first layout
    /// pass has measured anything.
    var visible: TimeRange {
        let half = seconds(fromPoints: length) / 2
        return TimeRange(start: center.addingTimeInterval(-half), end: center.addingTimeInterval(half))
    }

    /// Where `instant` sits along the track. Deliberately unclamped: a drag reads instants from
    /// beyond either edge.
    func position(of instant: Date) -> CGFloat {
        points(fromSeconds: instant.timeIntervalSince(visible.start))
    }

    func instant(atPosition position: CGFloat) -> Date {
        visible.start.addingTimeInterval(seconds(fromPoints: position))
    }

    /// The playhead moved by `points` of track — positive is forward in time. A horizontal drag
    /// passes the negated translation (dragging right reveals the past); a vertical one passes it
    /// as-is (dragging down reveals the future).
    func center(shiftedByPoints points: CGFloat) -> Date {
        center.addingTimeInterval(seconds(fromPoints: points))
    }

    private func seconds(fromPoints points: CGFloat) -> TimeInterval {
        guard pointsPerHour > 0 else { return 0 }
        return TimeInterval(points / pointsPerHour) * 3600
    }

    private func points(fromSeconds seconds: TimeInterval) -> CGFloat {
        CGFloat(seconds / 3600) * pointsPerHour
    }
}
