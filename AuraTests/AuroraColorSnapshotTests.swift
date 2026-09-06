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
