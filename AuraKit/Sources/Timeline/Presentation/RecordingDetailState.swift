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
    /// What the video slot holds — the picture, or the reason there is none.
    public let slot: RecordingSlot
    /// Whether the playhead is parked at — or following — the newest recorded footage. Owned by
    /// the view model, not derived from the instant: the player parks a couple of seconds behind
    /// the wall clock (segments land late), and that drift must not read as history.
    public let isLive: Bool
    /// False for an hour holding no footage at all: there is nothing to start or speed up, though
    /// the skips and the track stay live so the hour can be left.
    public let isPlayable: Bool
    /// The export range editor, when it is open. `nil` is ordinary playback — and is why the
    /// entry point, the day-overview bar and the transport can all read one property to decide
    /// whether they are on screen at all.
    public let export: ExportEditorState?
    /// Whether playback is currently fenced to the export selection. Separate from `isPlaying`,
    /// which stays the honest answer to "is the video moving".
    public let isPlayingSelection: Bool

    public init(
        cameraName: String,
        instant: Date,
        span: TimeRange,
        dayTimeline: DayTimeline,
        zoom: TimelineZoom,
        isPlaying: Bool,
        speed: PlaybackSpeed,
        slot: RecordingSlot,
        isLive: Bool,
        isPlayable: Bool,
        export: ExportEditorState?,
        isPlayingSelection: Bool
    ) {
        self.cameraName = cameraName
        self.instant = instant
        self.span = span
        self.dayTimeline = dayTimeline
        self.zoom = zoom
        self.isPlaying = isPlaying
        self.speed = speed
        self.slot = slot
        self.isLive = isLive
        self.isPlayable = isPlayable
        self.export = export
        self.isPlayingSelection = isPlayingSelection
    }

    public var isExporting: Bool { export != nil }

    /// The review marker under the playhead, if any — what the hero badge names.
    public var activeMarker: ReviewMarker? {
        MarkerNavigator.marker(at: instant, in: dayTimeline.markers)
    }

    /// Whether the "previous activity" transport button would move the playhead — false at the
    /// start of the marker list, so the button can disable itself instead of pressing to nothing.
    public var hasPreviousMarker: Bool {
        MarkerNavigator.marker(before: instant, in: dayTimeline.markers) != nil
    }

    /// The same, forward.
    public var hasNextMarker: Bool {
        MarkerNavigator.marker(after: instant, in: dayTimeline.markers) != nil
    }

    /// The calendar day the playhead is in — what the stepper walks and the overview bar draws.
    func day(in calendar: Calendar) -> TimeRange {
        TimeRange.day(containing: instant, in: calendar)
    }
}

/// What the video slot holds. The card — rim, glow, letterbox and the chrome floated over the
/// picture — exists only for `.footage`; every other case is drawn as a message on the aurora, in
/// the slot's place, so nothing is left behind to read as a broken card.
public enum RecordingSlot: Equatable, Sendable {
    case loading
    /// A picture is up: the recording, the live stream, or the low-resolution material a drag shows.
    case footage
    /// Nothing recorded under the playhead — a gap, an hour holding no footage, or the live edge
    /// before the newest segment has landed.
    case noFootage
    case failed
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
    /// Opens the range editor on the track already on screen, seeded around the playhead.
    public let beginExport: () -> Void
    public let cancelExport: () -> Void
    public let changeSelection: (ExportSelection) -> Void
    public let resetSelectionToPlayhead: () -> Void
    public let playSelection: () -> Void
    public let createExport: () -> Void
    /// Leaves export mode and hands the finished clip to the Exports tab.
    public let viewInExports: () -> Void
    public let playExport: () -> Void
    /// Dismisses a finished export and returns the panel to ordinary playback.
    public let finishExport: () -> Void

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
        goLive: @escaping () -> Void,
        beginExport: @escaping () -> Void,
        cancelExport: @escaping () -> Void,
        changeSelection: @escaping (ExportSelection) -> Void,
        resetSelectionToPlayhead: @escaping () -> Void,
        playSelection: @escaping () -> Void,
        createExport: @escaping () -> Void,
        viewInExports: @escaping () -> Void,
        playExport: @escaping () -> Void,
        finishExport: @escaping () -> Void
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
        self.beginExport = beginExport
        self.cancelExport = cancelExport
        self.changeSelection = changeSelection
        self.resetSelectionToPlayhead = resetSelectionToPlayhead
        self.playSelection = playSelection
        self.createExport = createExport
        self.viewInExports = viewInExports
        self.playExport = playExport
        self.finishExport = finishExport
    }

    /// Every verb silenced — for screenshots and previews, which render the chrome but drive nothing.
    @MainActor public static let inert = RecordingDetailActions(
        playPause: {}, skip: { _ in }, selectSpeed: { _ in }, selectZoom: { _ in },
        beginScrub: {}, scrub: { _ in }, endScrub: {}, seek: { _ in },
        stepDay: { _ in }, previousMarker: {}, nextMarker: {}, goLive: {},
        beginExport: {}, cancelExport: {}, changeSelection: { _ in }, resetSelectionToPlayhead: {},
        playSelection: {}, createExport: {}, viewInExports: {}, playExport: {}, finishExport: {}
    )
}
