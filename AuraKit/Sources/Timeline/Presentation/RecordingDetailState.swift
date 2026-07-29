import Foundation

import TimelineDomain

/// Everything the Timeline-detail screen renders, as values — decoupled from
/// `RecordingPlayerViewModel` so the whole layout is a pure function of its inputs and can be
/// snapshot-tested with literal state, no `AVPlayer` and no server.
public struct RecordingDetailState: Equatable, Sendable {
    public let cameraName: String
    /// The wall-clock instant under the playhead.
    public let instant: Date
    /// The history the track scrolls over: `[start, now]`.
    public let span: TimeRange
    /// This camera's markers, motion and gaps over `span`.
    public let dayTimeline: DayTimeline
    public let zoom: TimelineZoom
    public let isPlaying: Bool
    public let speed: PlaybackSpeed
    /// Whether the playhead sits over recorded footage; false inside a gap, where the hero says so.
    public let hasFootage: Bool
    /// Whether the playhead is parked at — or following — the newest recorded footage. Owned by
    /// the view model, not derived from the instant: the player parks a couple of seconds behind
    /// the wall clock (segments land late), and that drift must not read as history.
    public let isLive: Bool
    /// False for an hour holding no footage at all: there is nothing to start or speed up, though
    /// the skips and the track stay live so the hour can be left.
    public let isPlayable: Bool

    public init(
        cameraName: String,
        instant: Date,
        span: TimeRange,
        dayTimeline: DayTimeline,
        zoom: TimelineZoom,
        isPlaying: Bool,
        speed: PlaybackSpeed,
        hasFootage: Bool,
        isLive: Bool,
        isPlayable: Bool
    ) {
        self.cameraName = cameraName
        self.instant = instant
        self.span = span
        self.dayTimeline = dayTimeline
        self.zoom = zoom
        self.isPlaying = isPlaying
        self.speed = speed
        self.hasFootage = hasFootage
        self.isLive = isLive
        self.isPlayable = isPlayable
    }

    /// The review marker under the playhead, if any — what the hero badge names.
    public var activeMarker: ReviewMarker? {
        MarkerNavigator.marker(at: instant, in: dayTimeline.markers)
    }

    /// The calendar day the playhead is in — what the stepper walks and the overview bar draws.
    func day(in calendar: Calendar) -> TimeRange {
        TimeRange.day(containing: instant, in: calendar)
    }
}

/// What the layout can ask for. Grouped rather than passed as a dozen loose closures, so the
/// screen's verbs read as one list and a snapshot can silence them all at once.
public struct RecordingDetailActions {
    public let playPause: () -> Void
    public let skip: (TimeInterval) -> Void
    public let selectSpeed: (PlaybackSpeed) -> Void
    public let selectZoom: (TimelineZoom) -> Void
    public let beginScrub: () -> Void
    public let scrub: (Date) -> Void
    public let endScrub: () -> Void
    public let seek: (Date) -> Void
    public let stepDay: (Int) -> Void
    public let previousMarker: () -> Void
    public let nextMarker: () -> Void
    public let goLive: () -> Void

    public init(
        playPause: @escaping () -> Void,
        skip: @escaping (TimeInterval) -> Void,
        selectSpeed: @escaping (PlaybackSpeed) -> Void,
        selectZoom: @escaping (TimelineZoom) -> Void,
        beginScrub: @escaping () -> Void,
        scrub: @escaping (Date) -> Void,
        endScrub: @escaping () -> Void,
        seek: @escaping (Date) -> Void,
        stepDay: @escaping (Int) -> Void,
        previousMarker: @escaping () -> Void,
        nextMarker: @escaping () -> Void,
        goLive: @escaping () -> Void
    ) {
        self.playPause = playPause
        self.skip = skip
        self.selectSpeed = selectSpeed
        self.selectZoom = selectZoom
        self.beginScrub = beginScrub
        self.scrub = scrub
        self.endScrub = endScrub
        self.seek = seek
        self.stepDay = stepDay
        self.previousMarker = previousMarker
        self.nextMarker = nextMarker
        self.goLive = goLive
    }

    /// Every verb silenced — for screenshots and previews, which render the chrome but drive nothing.
    @MainActor public static let inert = RecordingDetailActions(
        playPause: {}, skip: { _ in }, selectSpeed: { _ in }, selectZoom: { _ in },
        beginScrub: {}, scrub: { _ in }, endScrub: {}, seek: { _ in },
        stepDay: { _ in }, previousMarker: {}, nextMarker: {}, goLive: {}
    )
}
