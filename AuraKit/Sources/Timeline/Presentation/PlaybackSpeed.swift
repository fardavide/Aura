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
}
