import SwiftUI

// Every colour in the app comes from here. The catalog carries the light/dark pair, so a token
// is appearance-aware for free and the same name works inside `Canvas` via `.color(_:)`.
extension ShapeStyle where Self == Color {
    // Surfaces
    public static var auroraBase: Color { Color("Base", bundle: .module) }
    public static var auroraNoFootage: Color { Color("NoFootage", bundle: .module) }
    public static var auroraSettingsSheet: Color { Color("SettingsSheet", bundle: .module) }
    public static var auroraSettingsBackdrop: Color { Color("SettingsBackdrop", bundle: .module) }
    public static var auroraSettingsRow: Color { Color("SettingsRow", bundle: .module) }
    // Text
    public static var auroraTextPrimary: Color { Color("TextPrimary", bundle: .module) }
    public static var auroraTextSecondary: Color { Color("TextSecondary", bundle: .module) }
    public static var auroraTextTertiary: Color { Color("TextTertiary", bundle: .module) }
    public static var auroraTextQuaternary: Color { Color("TextQuaternary", bundle: .module) }
    public static var auroraTextMuted: Color { Color("TextMuted", bundle: .module) }
    // Gradient stops / motion intensity
    public static var auroraGradientBlue: Color { Color("GradientBlue", bundle: .module) }
    public static var auroraGradientViolet: Color { Color("GradientViolet", bundle: .module) }
    public static var auroraGradientPink: Color { Color("GradientPink", bundle: .module) }
    // Severity + live
    public static var auroraLive: Color { Color("Live", bundle: .module) }
    public static var auroraAlertMarker: Color { Color("AlertMarker", bundle: .module) }
    public static var auroraAlertTagText: Color { Color("AlertTagText", bundle: .module) }
    public static var auroraAlertTagFill: Color { Color("AlertTagFill", bundle: .module) }
    public static var auroraAlertTagBorder: Color { Color("AlertTagBorder", bundle: .module) }
    public static var auroraDetection: Color { Color("Detection", bundle: .module) }
    public static var auroraDetectionInk: Color { Color("DetectionInk", bundle: .module) }
    // Glass
    public static var auroraSheetTint: Color { Color("SheetTint", bundle: .module) }
    public static var auroraSheetBorder: Color { Color("SheetBorder", bundle: .module) }
    public static var auroraChipFill: Color { Color("ChipFill", bundle: .module) }
    public static var auroraChipBorder: Color { Color("ChipBorder", bundle: .module) }
    public static var auroraVideoChipFill: Color { Color("VideoChipFill", bundle: .module) }
    public static var auroraVideoChipBorder: Color { Color("VideoChipBorder", bundle: .module) }
    public static var auroraWell: Color { Color("Well", bundle: .module) }
    public static var auroraGrabber: Color { Color("Grabber", bundle: .module) }
    public static var auroraRimBlue: Color { Color("RimBlue", bundle: .module) }
    public static var auroraRimViolet: Color { Color("RimViolet", bundle: .module) }
    public static var auroraRimPink: Color { Color("RimPink", bundle: .module) }
    // Washes
    public static var auroraWashViolet: Color { Color("WashViolet", bundle: .module) }
    public static var auroraWashPink: Color { Color("WashPink", bundle: .module) }
    public static var auroraWashBlue: Color { Color("WashBlue", bundle: .module) }
    // Track
    public static var auroraHatchFill: Color { Color("HatchFill", bundle: .module) }
    public static var auroraHatchLine: Color { Color("HatchLine", bundle: .module) }
    public static var auroraNowLine: Color { Color("NowLine", bundle: .module) }
    public static var auroraMidnight: Color { Color("Midnight", bundle: .module) }
}
