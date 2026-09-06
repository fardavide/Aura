import SwiftUI

extension Font {
    /// Urbanist at the style's size, scaled with Dynamic Type. Registers the fonts on first use.
    public static func aurora(_ style: AuroraTextStyle) -> Font {
        AuroraFonts.font(style.weight, size: style.size, relativeTo: style.relativeTo)
    }

    /// System rounded, monospaced digits, unscaled — for `Canvas` text (`@ScaledMetric` has no
    /// view to attach to there). Views use `.auroraNumerals(_:)` instead.
    public static func auroraNumerals(_ style: AuroraNumeralStyle) -> Font {
        .system(size: style.size, weight: style.weight, design: .rounded).monospacedDigit()
    }
}
