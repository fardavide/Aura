import SwiftUI

public extension EnvironmentValues {
    /// Diagnostic overlay for the Timeline detail, meant for the screenshot suite: outlines the
    /// camera **surface** (everything zoomed footage may cover, the glass panel included) and the
    /// initial camera **slot** (the space the resting video owns, which the controls must never
    /// cover). Off in the app; with it on, a layout regression that slides the panel over the
    /// slot is visible in the recorded baselines instead of being found on a phone.
    @Entry var cameraAreaHighlights: Bool = false
}
