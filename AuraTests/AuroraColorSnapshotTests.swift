import SwiftUI
import Testing

import CommonDesign

// `Color(_:bundle:)` against `Colors.xcassets` only resolves once the catalog has been compiled
// by `actool`, which happens under the app's `xcodebuild` build (and this host, AuraTests) but
// not under a bare `swift test` on the AuraKit package — that host copies the raw `.xcassets`
// folder without compiling it (verified: no `.car` is produced). This test therefore lives here,
// not in `CommonDesignTests` (tokens.md Risk R1).
@Suite
struct AuroraColorSnapshotTests {
    @Test
    func `given each catalog set when resolved in light and dark environments then the two resolved colours differ or the set is appearance-independent`() {
        // given
        var light = EnvironmentValues()
        light.colorScheme = .light
        var dark = EnvironmentValues()
        dark.colorScheme = .dark

        // when / then
        for entry in Scenario.allSets {
            let resolvedLight = entry.color.resolve(in: light)
            let resolvedDark = entry.color.resolve(in: dark)
            if entry.isAppearanceIndependent {
                #expect(resolvedLight == resolvedDark, "\(entry.name) should be appearance-independent")
            } else {
                #expect(resolvedLight != resolvedDark, "\(entry.name) should differ between light and dark")
            }
        }
    }

    /// A chip's fill is white in light mode, which is the right answer over the aurora background
    /// and no answer at all over an elevated white surface — a card, a sheet, the timeline panel.
    /// There the border is the only thing left to draw the control's shape, so it has to be ink
    /// rather than more white. A near-white border shipped a row of buttons that read as bare
    /// glyphs floating on the card, which is the dead-control failure mode by another route: the
    /// control works, but nothing on screen says it is one.
    @Test
    func `given the chip border over an elevated light surface then it still draws the shape`() {
        // given
        var light = EnvironmentValues()
        light.colorScheme = .light
        let surface = Color.auroraBase.resolve(in: light)

        // when
        let border = Color.auroraChipBorder.resolve(in: light).composited(over: surface)

        // then
        #expect(border.contrastRatio(against: surface) >= 1.2)
    }

    /// The same border over a dark card is a highlight rather than a shadow, and it already works —
    /// this pins it so a light-mode fix cannot be paid for out of dark mode.
    @Test
    func `given the chip border over an elevated dark surface then it still draws the shape`() {
        // given
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        let surface = Color.auroraBase.resolve(in: dark)

        // when
        let border = Color.auroraChipBorder.resolve(in: dark).composited(over: surface)

        // then
        #expect(border.contrastRatio(against: surface) >= 1.2)
    }

    @Test
    func `given AccentColor when resolved then light is C0368A and dark is FF8FC8`() {
        // given
        var light = EnvironmentValues()
        light.colorScheme = .light
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        let accent = Color("AccentColor", bundle: .main)

        // when
        let resolvedLight = accent.resolve(in: light)
        let resolvedDark = accent.resolve(in: dark)

        // then
        #expect(resolvedLight == Color(red: 0xC0 / 255, green: 0x36 / 255, blue: 0x8A / 255).resolve(in: light))
        #expect(resolvedDark == Color(red: 0xFF / 255, green: 0x8F / 255, blue: 0xC8 / 255).resolve(in: dark))
    }
}

/// Enough colour maths to ask "would anyone see this?" of a translucent token. Both tokens under
/// test are semi-transparent, so neither question can be answered from the token alone — it has to
/// be flattened onto the surface it is drawn over first.
private extension Color.Resolved {
    /// Source-over, in sRGB — the space `strokeBorder` actually blends in.
    func composited(over background: Color.Resolved) -> Color.Resolved {
        Color.Resolved(
            red: red * opacity + background.red * (1 - opacity),
            green: green * opacity + background.green * (1 - opacity),
            blue: blue * opacity + background.blue * (1 - opacity),
            opacity: 1
        )
    }

    /// WCAG 2.1 relative luminance, off the linearised components the type already carries.
    var relativeLuminance: Float {
        0.2126 * linearRed + 0.7152 * linearGreen + 0.0722 * linearBlue
    }

    /// WCAG 2.1 contrast ratio. Both colours must already be opaque.
    func contrastRatio(against other: Color.Resolved) -> Float {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

private struct Scenario {
    let name: String
    let color: Color
    let isAppearanceIndependent: Bool

    static let allSets: [Scenario] = [
        Scenario(name: "Base", color: .auroraBase, isAppearanceIndependent: false),
        Scenario(name: "NoFootage", color: .auroraNoFootage, isAppearanceIndependent: false),
        Scenario(name: "SettingsSheet", color: .auroraSettingsSheet, isAppearanceIndependent: false),
        Scenario(name: "SettingsBackdrop", color: .auroraSettingsBackdrop, isAppearanceIndependent: false),
        Scenario(name: "TextPrimary", color: .auroraTextPrimary, isAppearanceIndependent: false),
        Scenario(name: "TextSecondary", color: .auroraTextSecondary, isAppearanceIndependent: false),
        Scenario(name: "TextTertiary", color: .auroraTextTertiary, isAppearanceIndependent: false),
        Scenario(name: "TextQuaternary", color: .auroraTextQuaternary, isAppearanceIndependent: false),
        Scenario(name: "TextMuted", color: .auroraTextMuted, isAppearanceIndependent: false),
        Scenario(name: "GradientBlue", color: .auroraGradientBlue, isAppearanceIndependent: true),
        Scenario(name: "GradientViolet", color: .auroraGradientViolet, isAppearanceIndependent: true),
        Scenario(name: "GradientPink", color: .auroraGradientPink, isAppearanceIndependent: true),
        Scenario(name: "Live", color: .auroraLive, isAppearanceIndependent: true),
        Scenario(name: "AlertMarker", color: .auroraAlertMarker, isAppearanceIndependent: true),
        Scenario(name: "AlertTagText", color: .auroraAlertTagText, isAppearanceIndependent: false),
        Scenario(name: "AlertTagFill", color: .auroraAlertTagFill, isAppearanceIndependent: false),
        Scenario(name: "AlertTagBorder", color: .auroraAlertTagBorder, isAppearanceIndependent: false),
        Scenario(name: "Detection", color: .auroraDetection, isAppearanceIndependent: false),
        Scenario(name: "DetectionInk", color: .auroraDetectionInk, isAppearanceIndependent: true),
        Scenario(name: "SheetTint", color: .auroraSheetTint, isAppearanceIndependent: false),
        Scenario(name: "SheetBorder", color: .auroraSheetBorder, isAppearanceIndependent: false),
        Scenario(name: "ChipFill", color: .auroraChipFill, isAppearanceIndependent: false),
        Scenario(name: "ChipBorder", color: .auroraChipBorder, isAppearanceIndependent: false),
        Scenario(name: "VideoChipFill", color: .auroraVideoChipFill, isAppearanceIndependent: true),
        Scenario(name: "VideoChipBorder", color: .auroraVideoChipBorder, isAppearanceIndependent: true),
        Scenario(name: "Well", color: .auroraWell, isAppearanceIndependent: false),
        Scenario(name: "Grabber", color: .auroraGrabber, isAppearanceIndependent: false),
        Scenario(name: "RimBlue", color: .auroraRimBlue, isAppearanceIndependent: false),
        Scenario(name: "RimViolet", color: .auroraRimViolet, isAppearanceIndependent: false),
        Scenario(name: "RimPink", color: .auroraRimPink, isAppearanceIndependent: false),
        Scenario(name: "WashViolet", color: .auroraWashViolet, isAppearanceIndependent: false),
        Scenario(name: "WashPink", color: .auroraWashPink, isAppearanceIndependent: false),
        Scenario(name: "WashBlue", color: .auroraWashBlue, isAppearanceIndependent: false),
        Scenario(name: "HatchFill", color: .auroraHatchFill, isAppearanceIndependent: false),
        Scenario(name: "HatchLine", color: .auroraHatchLine, isAppearanceIndependent: false),
        Scenario(name: "NowLine", color: .auroraNowLine, isAppearanceIndependent: false),
        Scenario(name: "Midnight", color: .auroraMidnight, isAppearanceIndependent: false),
        Scenario(name: "SettingsRow", color: .auroraSettingsRow, isAppearanceIndependent: false),
    ]
}
