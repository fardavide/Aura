import SwiftUI

public enum AuroraGradient {
    /// Blue → violet → pink, the brand gradient.
    public static let stops = Gradient(colors: [.auroraGradientBlue, .auroraGradientViolet, .auroraGradientPink])
    /// Violet .9 → pink .9 — badge and selected-chip fill.
    public static let badgeStops = Gradient(colors: [
        .auroraGradientViolet.opacity(0.9), .auroraGradientPink.opacity(0.9),
    ])
    /// Blue → pink — the playhead line.
    public static let playheadLineStops = Gradient(colors: [.auroraGradientBlue, .auroraGradientPink])
    /// Violet → pink — the playhead dot.
    public static let playheadDotStops = Gradient(colors: [.auroraGradientViolet, .auroraGradientPink])
    /// Bright at both corners, faint in the middle — sheet and frame rim (values per appearance in the catalog).
    public static let rimStops = Gradient(colors: [.auroraRimBlue, .auroraRimViolet, .auroraRimPink])

    /// 135° — chrome: titles, buttons, badges, selected segments.
    public static let diagonal = LinearGradient(gradient: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    /// 90° (top → bottom) — video frames and the vertical playhead.
    public static let vertical = LinearGradient(gradient: stops, startPoint: .top, endPoint: .bottom)
    public static let badge = LinearGradient(gradient: badgeStops, startPoint: .topLeading, endPoint: .bottomTrailing)
    public static let rim = LinearGradient(gradient: rimStops, startPoint: .topLeading, endPoint: .bottomTrailing)
}
