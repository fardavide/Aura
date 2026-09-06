import SwiftUI

/// Severity as the design system sees it: two tones, shared by camera activity and review
/// markers (decision #10). Feature code switches its own severity enum into this at the call site.
public enum AuroraSeverityTone: Sendable {
    case alert
    case detection
}

public enum AuroraTrack {
    // Metrics (points)
    public static let nowLineWidth: CGFloat = 1.3
    public static let nowLineDash: [CGFloat] = [4, 4]
    public static let midnightLineWidth: CGFloat = 1
    public static let playheadLineWidth: CGFloat = 2
    public static let playheadDotDiameter: CGFloat = 12
    public static let playheadDotBorder: CGFloat = 2
    public static let wellCornerRadius: CGFloat = 12

    /// Motion intensity 0…100 → blue (< 35), violet (< 65), pink.
    public static func motionColor(intensity: Double) -> Color {
        switch intensity {
        case ..<35: .auroraGradientBlue
        case ..<65: .auroraGradientViolet
        default: .auroraGradientPink
        }
    }

    public static func markerColor(for tone: AuroraSeverityTone) -> Color {
        switch tone {
        case .alert: .auroraAlertMarker
        case .detection: .auroraDetection
        }
    }

    // Canvas shadings — same tokens, `GraphicsContext` spelling.
    public static var hatchFill: GraphicsContext.Shading { .color(.auroraHatchFill) }
    public static var hatchLine: GraphicsContext.Shading { .color(.auroraHatchLine) }
    public static var nowLine: GraphicsContext.Shading { .color(.auroraNowLine) }
    public static var midnight: GraphicsContext.Shading { .color(.auroraMidnight) }
    public static var nowLineStyle: StrokeStyle { StrokeStyle(lineWidth: nowLineWidth, dash: nowLineDash) }

    /// The gradient playhead for Canvas renderers (`DayOverviewBar`): a 2pt blue→pink line
    /// across `rect` plus the violet→pink dot with white border and pink glow at `dotCenter`.
    public static func drawPlayhead(in context: inout GraphicsContext, line: CGRect, dotCenter: CGPoint) {
        drawPlayheadLine(in: &context, line: line)
        let dot = CGRect(
            x: dotCenter.x - playheadDotDiameter / 2, y: dotCenter.y - playheadDotDiameter / 2,
            width: playheadDotDiameter, height: playheadDotDiameter
        )
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .auroraGradientPink.opacity(0.8), radius: 6))
            layer.fill(Path(ellipseIn: dot), with: .linearGradient(
                AuroraGradient.playheadDotStops, startPoint: CGPoint(x: dot.minX, y: dot.minY), endPoint: CGPoint(x: dot.maxX, y: dot.maxY)
            ))
        }
        context.stroke(Path(ellipseIn: dot.insetBy(dx: playheadDotBorder / 2, dy: playheadDotBorder / 2)), with: .color(.white), lineWidth: playheadDotBorder)
    }

    /// Just the gradient line, for a caller compositing its own dot (the detail ruler).
    public static func drawPlayheadLine(in context: inout GraphicsContext, line: CGRect) {
        let lineShading = GraphicsContext.Shading.linearGradient(
            AuroraGradient.playheadLineStops,
            startPoint: CGPoint(x: line.midX, y: line.minY),
            endPoint: CGPoint(x: line.midX, y: line.maxY)
        )
        context.fill(Path(line), with: lineShading)
    }
}
