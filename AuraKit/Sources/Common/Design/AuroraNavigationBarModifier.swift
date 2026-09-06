import SwiftUI

extension View {
    /// Hides the system navigation bar chrome so a screen can draw its own large title over the
    /// aurora background. `ToolbarPlacement.navigationBar` is unavailable on macOS, so this is the
    /// one sanctioned home for the `#if os` feature code must not scatter for itself.
    public func auroraHiddenNavigationBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}
