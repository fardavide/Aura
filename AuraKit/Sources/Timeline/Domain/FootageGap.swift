/// A span with no recorded footage — drawn dimmed on the timeline so gaps are visible.
public struct FootageGap: Equatable, Sendable {
    public let range: TimeRange

    public init(range: TimeRange) {
        self.range = range
    }
}
