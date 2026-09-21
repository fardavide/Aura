import Foundation

/// The named densities the timeline is drawn at — the zoom pill cycles through these, and the
/// pinch zooms continuously between the extremes. The same scale drives both axes so the bar
/// spacing reads identically whether the card is horizontal or vertical.
public enum TimelineZoom: CaseIterable, Sendable {
    /// One point per second. Added for the export range editor: at `hour` — the ladder's previous
    /// floor — the editor's 1:30 seed is 12 points wide, narrower than the handle bars either side
    /// of it, so no amount of handle design makes it grabbable. It is a permanent rung rather than
    /// an export-only density because a control that reads "Hour" while showing six minutes lies
    /// about its own value, and because fine scrubbing is useful on its own.
    case minute
    case hour, day, week

    var pointsPerHour: CGFloat {
        switch self {
        case .minute: 3_600
        case .hour: 480
        case .day: 120
        case .week: 36
        }
    }

    public var title: String {
        switch self {
        case .minute: "Minute"
        case .hour: "Hour"
        case .day: "Day"
        case .week: "Week"
        }
    }

    /// The label where four full words do not fit — the segmented control on a 393 pt phone and
    /// the rail's cycling chip. Only `minute` actually shortens; the rest are already short.
    public var compactTitle: String {
        switch self {
        case .minute: "Min"
        case .hour, .day, .week: title
        }
    }

    public var icon: String {
        switch self {
        case .minute: "timer"
        case .hour: "clock"
        case .day: "sun.max"
        case .week: "calendar"
        }
    }

    /// Whether a strip of preview stills reads as a filmstrip at this density. Frigate samples one
    /// still per 600 s, which is 80 pt at `hour` and 600 pt at `minute` — a single stretched frame
    /// pretending to be a strip. Precision mode revisits this with a finer slot grid; until then
    /// the filmstrip is an Hour-only affordance.
    var showsFilmstrip: Bool {
        self == .hour
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

    /// Keeps a pinched density inside the designed range — the week and minute presets bound it.
    static func clamped(_ density: CGFloat) -> CGFloat {
        min(max(density, TimelineZoom.week.pointsPerHour), TimelineZoom.minute.pointsPerHour)
    }
}
