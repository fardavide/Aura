import SwiftUI

/// The 45° hatch that marks a stretch the camera has no footage for — recorded-but-quiet reads as
/// bare track, so "nothing was recorded" needs a texture of its own rather than another shade.
/// Shared by the scrub track and the day-overview bar so the two agree.
enum TimelineHatch {
    /// Distance between the diagonal lines.
    private static let pitch: CGFloat = 7

    static func fill(_ rect: CGRect, in context: GraphicsContext) {
        context.fill(Path(rect), with: .color(.gray.opacity(0.08)))
        context.drawLayer { layer in
            layer.clip(to: Path(rect))
            // The run equals the band's height, so the slope stays 45° whatever the band's shape.
            let run = rect.height
            var hatch = Path()
            var origin = rect.minX - run
            while origin < rect.maxX {
                hatch.move(to: CGPoint(x: origin, y: rect.maxY))
                hatch.addLine(to: CGPoint(x: origin + run, y: rect.minY))
                origin += pitch
            }
            layer.stroke(hatch, with: .color(.gray.opacity(0.3)), lineWidth: 1)
        }
    }
}
