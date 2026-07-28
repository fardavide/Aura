/// One window's worth of overlays — what a chunked timeline read yields, and the unit a refresh
/// folds into the already-loaded timeline via `DayTimeline.replacing(_:)`.
public struct DayTimelineSlice: Equatable, Sendable {
    public let window: TimeRange
    public let overlays: DayTimeline

    public init(window: TimeRange, overlays: DayTimeline) {
        self.window = window
        self.overlays = overlays
    }
}
