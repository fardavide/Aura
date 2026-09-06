import SwiftUI

import CommonDesign

/// The 45° hatch that marks a stretch the camera has no footage for — recorded-but-quiet reads as
/// bare track, so "nothing was recorded" needs a texture of its own rather than another shade.
/// Shared by the scrub track and the day-overview bar so the two agree.
enum TimelineHatch {
    /// Distance between the diagonal lines.
    private static let pitch: CGFloat = 7

    /// The diagonal lines' endpoints, pure geometry so it is unit-testable without a
    /// `GraphicsContext`. The run equals the band's height, so the slope stays 45° whatever the
    /// band's shape.
    static func lineSegments(in rect: CGRect) -> [(CGPoint, CGPoint)] {
        let run = rect.height
        var segments: [(CGPoint, CGPoint)] = []
        var origin = rect.minX - run
        while origin < rect.maxX {
            segments.append((CGPoint(x: origin, y: rect.maxY), CGPoint(x: origin + run, y: rect.minY)))
            origin += pitch
        }
        return segments
    }

    static func fill(_ rect: CGRect, in context: GraphicsContext) {
        context.fill(Path(rect), with: AuroraTrack.hatchFill)
        context.drawLayer { layer in
            layer.clip(to: Path(rect))
            var hatch = Path()
            for (start, end) in lineSegments(in: rect) {
                hatch.move(to: start)
                hatch.addLine(to: end)
            }
            layer.stroke(hatch, with: AuroraTrack.hatchLine, lineWidth: 1)
        }
    }
}
