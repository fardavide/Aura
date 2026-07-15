/// A tally of events over a window (the grid's "today" summary): the total plus a per-label
/// breakdown, ordered most-frequent first, so the card can read "14 events · 9 person · 5 car".
public struct EventCount: Equatable, Sendable {
    public let total: Int
    public let breakdown: [LabelCount]

    public init(total: Int, breakdown: [LabelCount]) {
        self.total = total
        self.breakdown = breakdown
    }

    public struct LabelCount: Equatable, Sendable {
        public let label: String
        public let count: Int

        public init(label: String, count: Int) {
            self.label = label
            self.count = count
        }
    }
}
