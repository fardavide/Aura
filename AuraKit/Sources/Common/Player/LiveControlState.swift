/// The transport state `LiveControlBar` renders — decoupled from `LivePlayerModel` so the bar is a
/// pure function of value inputs (and can be snapshot-tested with literal state, no `AVPlayer`).
public struct LiveControlState: Equatable, Sendable {
    public let isPlaying: Bool
    public let isMuted: Bool
    public let isPictureInPictureSupported: Bool
    public let isPictureInPictureActive: Bool
    public let isPictureInPicturePossible: Bool

    public init(
        isPlaying: Bool,
        isMuted: Bool,
        isPictureInPictureSupported: Bool,
        isPictureInPictureActive: Bool,
        isPictureInPicturePossible: Bool
    ) {
        self.isPlaying = isPlaying
        self.isMuted = isMuted
        self.isPictureInPictureSupported = isPictureInPictureSupported
        self.isPictureInPictureActive = isPictureInPictureActive
        self.isPictureInPicturePossible = isPictureInPicturePossible
    }
}
