import Foundation

/// The named densities the timeline is drawn at — the zoom pill cycles through these, and the
/// pinch zooms continuously between the extremes. The same scale drives both axes so the bar
/// spacing reads identically whether the card is horizontal or vertical.
enum TimelineZoom: CaseIterable {
    case hour, day, week

    var pointsPerHour: CGFloat {
        switch self {
        case .hour: 480
        case .day: 120
        case .week: 36
        }
    }

    var title: String {
        switch self {
        case .hour: "Hour"
        case .day: "Day"
        case .week: "Week"
        }
    }

    var icon: String {
        switch self {
        case .hour: "clock"
        case .day: "sun.max"
        case .week: "calendar"
        }
    }

    var next: TimelineZoom {
        let all = Self.allCases
        return all[(all.firstIndex(of: self).map { $0 + 1 } ?? 0) % all.count]
    }

    /// The preset nearest to `density` in log space — zoom is multiplicative, so the midpoint
    /// between day (120) and hour (480) is their geometric mean, 240.
    static func nearest(to density: CGFloat) -> TimelineZoom {
        let clamped = clamped(density)
        let byLogDistance = allCases.min {
            abs(log(Double($0.pointsPerHour / clamped))) < abs(log(Double($1.pointsPerHour / clamped)))
        }
        return byLogDistance ?? .day
    }

    /// Keeps a pinched density inside the designed range — the week and hour presets bound it.
    static func clamped(_ density: CGFloat) -> CGFloat {
        min(max(density, TimelineZoom.week.pointsPerHour), TimelineZoom.hour.pointsPerHour)
    }
}
