/// How fast recorded footage plays back. Mirrors the ladder Frigate's own client offers, so the
/// same recording behaves the same way in either.
public enum PlaybackSpeed: Double, CaseIterable, Sendable {
    case oneX = 1
    case twoX = 2
    case fourX = 4
    case eightX = 8

    public var rate: Float {
        Float(rawValue)
    }

    public var title: String {
        "\(Int(rawValue))×"
    }

    /// The next rung up, wrapping round at the top — the slim landscape scrubber has room for one
    /// speed button rather than the whole ladder, so it steps through them.
    public var next: PlaybackSpeed {
        let ladder = PlaybackSpeed.allCases
        guard let index = ladder.firstIndex(of: self) else { return .oneX }
        return ladder[(index + 1) % ladder.count]
    }
}
