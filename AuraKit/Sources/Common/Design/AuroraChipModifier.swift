import SwiftUI

public enum AuroraGlassSurface: Sendable {
    case chrome
    case video

    var fill: Color {
        switch self {
        case .chrome: .auroraChipFill
        case .video: .auroraVideoChipFill
        }
    }

    var border: Color {
        switch self {
        case .chrome: .auroraChipBorder
        case .video: .auroraVideoChipBorder
        }
    }
}

extension View {
    /// Capsule glass chip. `over: .video` for anything drawn on top of a player.
    public func auroraChip(over surface: AuroraGlassSurface = .chrome) -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(surface.fill), in: Capsule())
            .overlay { Capsule().strokeBorder(surface.border, lineWidth: 1) }
    }
}
