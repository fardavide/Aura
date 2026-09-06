import Foundation
import SwiftUI

import TimelineDomain

/// Maps a time range and a cross-axis band onto a rectangle for the chosen axis, so every shape is
/// expressed once in time terms rather than twice in points.
struct TrackGeometry {
    let axis: Axis
    let viewport: TimelineViewport
    let size: CGSize

    var crossExtent: CGFloat { axis == .horizontal ? size.height : size.width }
    private var timeExtent: CGFloat { axis == .horizontal ? size.width : size.height }

    func rect(from start: Date, to end: Date, crossFrom: CGFloat, crossTo: CGFloat) -> CGRect {
        let low = viewport.position(of: start)
        let high = viewport.position(of: end)
        switch axis {
        case .horizontal:
            return CGRect(x: low, y: crossFrom, width: high - low, height: crossTo - crossFrom)
        case .vertical:
            // Newest at the top, so the axis is flipped against the forward position.
            return CGRect(x: crossFrom, y: timeExtent - high, width: crossTo - crossFrom, height: high - low)
        }
    }

    /// A hairline across the whole cross axis at one instant — a day divider or the live edge.
    func line(at instant: Date) -> Path {
        let rect = rect(from: instant, to: instant, crossFrom: 0, crossTo: crossExtent)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }

    /// Trims a rect along the **time** axis, never below a hairline — the separator between
    /// neighbouring bars, which must not consume a bar that is already thin.
    func narrowed(_ rect: CGRect, by points: CGFloat) -> CGRect {
        switch axis {
        case .horizontal:
            let trimmed = max(1, rect.width - points)
            return CGRect(x: rect.minX, y: rect.minY, width: trimmed, height: rect.height)
        case .vertical:
            let trimmed = max(1, rect.height - points)
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: trimmed)
        }
    }

    /// Grows a rect along the **time** axis to a minimum, keeping it centred on what it covers.
    func lengthened(_ rect: CGRect, toAtLeast minimum: CGFloat) -> CGRect {
        switch axis {
        case .horizontal:
            guard rect.width < minimum else { return rect }
            return CGRect(x: rect.midX - minimum / 2, y: rect.minY, width: minimum, height: rect.height)
        case .vertical:
            guard rect.height < minimum else { return rect }
            return CGRect(x: rect.minX, y: rect.midY - minimum / 2, width: rect.width, height: minimum)
        }
    }
}
