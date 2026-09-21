import Foundation
import SwiftUI

import TimelineDomain

/// Which boundary of the clip a gesture is holding.
public enum ExportHandleSide: Equatable, Sendable {
    case start
    case end
}

/// Where the export handles sit on the track, and who wins a touch that could belong to either.
///
/// Split out from the view because it is the part with actual rules in it: the knobs sit *outside*
/// the selection so the interior stays draggable however short the clip gets, the bars reserve the
/// first 22 pt at each end, and an ambiguous touch resolves to the nearer bar — falling back to
/// whichever handle moved last, so the tie is deterministic rather than a function of view order.
struct ExportTrackLayout {
    let axis: Axis
    let viewport: TimelineViewport
    /// The track's cross-axis size.
    let thickness: CGFloat
    let selection: ExportSelection

    /// Bar 3 pt, knob 14 × 28 flush outside it (design §10).
    static let barWidth: CGFloat = 3
    static let knobWidth: CGFloat = 14
    static let knobHeight: CGFloat = 28
    static let knobRadius: CGFloat = 7
    /// The 44 pt target overhangs the 72 pt track by 8 pt top and bottom.
    static let targetWidth: CGFloat = 44
    static let targetOverhang: CGFloat = 8
    /// What each bar reserves of the selection's own interior.
    static let barReserve: CGFloat = 22
    /// Below this the grab bar is not drawn — there is nowhere honest to put it.
    static let grabBarMinimumLength: CGFloat = 44
    static let grabBarSize = CGSize(width: 24, height: 3)
    static let grabBarInset: CGFloat = 6

    var startPosition: CGFloat { position(of: selection.start) }
    var endPosition: CGFloat { position(of: selection.end) }

    /// Always positive — the selection's extent along the axis, whichever way the axis runs.
    var selectionLength: CGFloat { abs(endPosition - startPosition) }

    /// The leading edge of the selection *in screen order*, which a vertical track reverses.
    var selectionOrigin: CGFloat { min(startPosition, endPosition) }

    func position(of instant: Date) -> CGFloat {
        let forward = viewport.position(of: instant)
        // Vertical runs newest-at-top, so screen position counts back from the far end.
        return axis == .horizontal ? forward : viewport.length - forward
    }

    /// The knob, flush against the outside of its bar so the selection's interior is never eaten.
    func knobRect(_ side: ExportHandleSide) -> CGRect {
        let at = side == .start ? startPosition : endPosition
        let outward = outwardDirection(side)
        let near = at + outward * Self.barWidth / 2
        let far = near + outward * Self.knobWidth
        switch axis {
        case .horizontal:
            return CGRect(
                x: min(near, far), y: (thickness - Self.knobHeight) / 2,
                width: Self.knobWidth, height: Self.knobHeight
            )
        case .vertical:
            return CGRect(
                x: (thickness - Self.knobHeight) / 2, y: min(near, far),
                width: Self.knobHeight, height: Self.knobWidth
            )
        }
    }

    /// Centred on the bar, not on the knob — the bar is the truth the user is aiming at.
    func targetRect(_ side: ExportHandleSide) -> CGRect {
        let at = side == .start ? startPosition : endPosition
        switch axis {
        case .horizontal:
            return CGRect(
                x: at - Self.targetWidth / 2, y: -Self.targetOverhang,
                width: Self.targetWidth, height: thickness + Self.targetOverhang * 2
            )
        case .vertical:
            return CGRect(
                x: -Self.targetOverhang, y: at - Self.targetWidth / 2,
                width: thickness + Self.targetOverhang * 2, height: Self.targetWidth
            )
        }
    }

    var showsGrabBar: Bool {
        selectionLength >= Self.grabBarMinimumLength
    }

    /// What is left of the interior once both bars have taken their 22 pt. `nil` at the minimum,
    /// where there is nothing left — the range moves by keyboard, VoiceOver or zooming out
    /// instead, and no affordance is drawn promising otherwise.
    var regionDragRange: ClosedRange<CGFloat>? {
        let low = selectionOrigin + Self.barReserve
        let high = selectionOrigin + selectionLength - Self.barReserve
        return low < high ? low...high : nil
    }

    /// The nearer bar, and on an exact tie the handle that moved last.
    func handle(closestTo position: CGFloat, lastMoved: ExportHandleSide) -> ExportHandleSide {
        let toStart = abs(position - startPosition)
        let toEnd = abs(position - endPosition)
        if toStart == toEnd { return lastMoved }
        return toStart < toEnd ? .start : .end
    }

    /// Which way is "out of the selection" for this side, in screen coordinates.
    private func outwardDirection(_ side: ExportHandleSide) -> CGFloat {
        let startsFirst = startPosition <= endPosition
        switch side {
        case .start: return startsFirst ? -1 : 1
        case .end: return startsFirst ? 1 : -1
        }
    }
}
