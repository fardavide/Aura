/// The events subtitle's underlying counts: a day's total and its per-label breakdown, most
/// frequent first. Mirrors `CamerasDomain.EventCount` deliberately rather than depending on it
/// (feature-vertical rule; the Cameras type is reached through a different repository).
public struct EventsSummary: Equatable, Sendable {
    public struct LabelCount: Equatable, Sendable {
        public let label: String
        public let count: Int

        public init(label: String, count: Int) {
            self.label = label
            self.count = count
        }
    }

    public let total: Int
    public let breakdown: [LabelCount]

    public init(total: Int, breakdown: [LabelCount]) {
        self.total = total
        self.breakdown = breakdown
    }
}
