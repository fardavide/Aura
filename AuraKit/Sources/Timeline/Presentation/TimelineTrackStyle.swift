import SwiftUI

import CommonDesign
import TimelineDomain

/// The one visual language every timeline strip draws in — the tab's histogram, the detail's
/// scrub track and the day-overview bar: motion bars coloured by intensity, review markers as
/// gradient/amber pills in a thin lane of their own, and no-footage stretches hatched
/// (`TimelineHatch`). One vocabulary, wherever a timeline appears — the paint itself lives in
/// `AuroraTrack` (CommonDesign); this delegates to it.
enum TimelineTrackStyle {
    /// Cross-axis room between the track's edge and the marker lane.
    static let laneInset: CGFloat = 3
    static let laneThickness: CGFloat = 8
    /// Clear space between the lane and the tallest a motion bar may grow.
    static let laneClearance: CGFloat = 6
    /// The least length a marker pill draws at — a seconds-long marker would otherwise be
    /// invisible at week density.
    static let minimumMarkerLength: CGFloat = laneThickness / 2
    /// The hairline between neighbouring motion bars: without it, contiguous buckets weld into
    /// one block and the strip stops reading as a series of measurements.
    static let motionBarSeparator: CGFloat = 1

    /// Motion intensity 0…100 → blue (< 35), violet (< 65), pink.
    static func motionColor(intensity: Int) -> Color {
        AuroraTrack.motionColor(intensity: Double(intensity))
    }

    static func markerColor(for severity: ReviewSeverity) -> Color {
        AuroraTrack.markerColor(for: severity == .alert ? .alert : .detection)
    }

    static func fillMarkerPill(_ rect: CGRect, severity: ReviewSeverity, in context: GraphicsContext) {
        context.fill(
            Path(roundedRect: rect, cornerRadius: laneThickness / 2),
            with: .color(markerColor(for: severity))
        )
    }
}
