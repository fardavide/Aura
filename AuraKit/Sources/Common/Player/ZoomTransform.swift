import SwiftUI

/// Digital zoom + pan for viewport-filling content, as pure clamped math.
///
/// Rendering contract: the content is drawn with `.scaleEffect(scale, anchor: .center)`
/// followed by `.offset(offset)` inside a clipped, viewport-sized container. The pan offset
/// is clamped so the content edges never pull inside the viewport, and magnification keeps
/// the content point under the gesture anchor stationary.
public struct ZoomTransform: Equatable, Sendable {
    public let scaleRange: ClosedRange<CGFloat>
    public private(set) var scale: CGFloat
    public private(set) var offset: CGSize

    public init(scaleRange: ClosedRange<CGFloat>) {
        self.scaleRange = scaleRange
        self.scale = scaleRange.lowerBound
        self.offset = .zero
    }

    public static func standard() -> ZoomTransform {
        ZoomTransform(scaleRange: 1...4)
    }

    public var isZoomed: Bool { scale > scaleRange.lowerBound }

    /// Applies the gesture's cumulative `magnification` relative to this (gesture-start)
    /// transform, anchored at `anchor` in viewport unit coordinates, then clamps.
    public func magnified(by magnification: CGFloat, anchor: UnitPoint, viewport: CGSize) -> ZoomTransform {
        let newScale = (scale * magnification).clamped(to: scaleRange)
        let ratio = newScale / scale
        let anchorFromCenter = CGSize(
            width: (anchor.x - 0.5) * viewport.width,
            height: (anchor.y - 0.5) * viewport.height
        )
        let newOffset = CGSize(
            width: anchorFromCenter.width * (1 - ratio) + offset.width * ratio,
            height: anchorFromCenter.height * (1 - ratio) + offset.height * ratio
        )
        var next = self
        next.scale = newScale
        next.offset = Self.clamped(newOffset, scale: newScale, viewport: viewport)
        return next
    }

    /// Applies the gesture's cumulative `translation` relative to this (gesture-start)
    /// transform, then clamps. At minimum scale the clamp keeps the offset at zero.
    public func panned(by translation: CGSize, viewport: CGSize) -> ZoomTransform {
        let newOffset = CGSize(
            width: offset.width + translation.width,
            height: offset.height + translation.height
        )
        var next = self
        next.offset = Self.clamped(newOffset, scale: scale, viewport: viewport)
        return next
    }

    /// Double-tap behavior: zoomed → identity; identity → 2x anchored at the tap point.
    public func togglingZoom(at anchor: UnitPoint, viewport: CGSize) -> ZoomTransform {
        isZoomed ? reset() : magnified(by: 2, anchor: anchor, viewport: viewport)
    }

    public func reset() -> ZoomTransform {
        ZoomTransform(scaleRange: scaleRange)
    }

    private static func clamped(_ offset: CGSize, scale: CGFloat, viewport: CGSize) -> CGSize {
        let bound = CGSize(
            width: max(0, viewport.width * (scale - 1) / 2),
            height: max(0, viewport.height * (scale - 1) / 2)
        )
        return CGSize(
            width: offset.width.clamped(to: -bound.width...bound.width),
            height: offset.height.clamped(to: -bound.height...bound.height)
        )
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
