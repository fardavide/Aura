import SwiftUI

public extension EnvironmentValues {
    /// Diagnostic overlay for the Timeline detail, meant for the screenshot suite: outlines the
    /// camera **surface** (everything zoomed footage may cover, the glass panel included) and the
    /// initial camera **slot** (the space the resting video owns, which the controls must never
    /// cover). Off in the app; with it on, a layout regression that slides the panel over the
    /// slot is visible in the recorded baselines instead of being found on a phone.
    @Entry var cameraAreaHighlights: Bool = false
}

/// The diagnostic outline colours `cameraAreaHighlights` draws with. Kept off the design system on
/// purpose — an outline that could pass for real chrome would defeat the point — and named here,
/// the file already dedicated to the flag, so the shared "no raw `.orange`/`.green`" merge gate can
/// exclude this one path instead of special-casing the diagnostic's semantics.
enum CameraAreaHighlights {
    static let surface: Color = .orange
    static let slot: Color = .green
}
