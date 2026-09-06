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
