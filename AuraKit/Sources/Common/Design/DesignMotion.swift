import SwiftUI

public enum DesignMotion: Equatable, Sendable {
    /// Idle animations run (live-pill blink, segmented-control slide).
    case animated
    /// Every idle animation renders its first frame and stays there — snapshot tests.
    case still
}

extension EnvironmentValues {
    @Entry public var designMotion: DesignMotion = .animated
}

extension Animation {
    /// The one curve for a hero swap. Both walls that promote a camera into the large tile — the
    /// Cameras grid and the Timeline grid — travel on it, so the same event never reads as two
    /// different gestures depending on which tab you are looking at.
    public static let auroraHeroSwap: Animation = .smooth(duration: 0.35)

    /// The one crossfade for a video slot losing or regaining its picture — the picture, rim, glow
    /// and chrome out and the message in, or the reverse — on the Timeline detail hero and the
    /// Timeline tiles alike. Ease-out like the zoom chrome's border fade, so the two never fight.
    public static let auroraSlotCrossfade: Animation = .easeOut(duration: 0.2)
}
