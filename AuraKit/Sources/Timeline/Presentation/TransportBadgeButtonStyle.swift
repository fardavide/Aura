import SwiftUI

/// The same press and disabled treatment as `TransportCircleButtonStyle`, for the badge-labelled
/// buttons (the speed pill, the Live pill) — `auroraBadge` renders no press feedback at all under
/// `.buttonStyle(.plain)`. Paints nothing itself: the badge is the label, so this and
/// `TransportCircleButtonStyle` share the nested-view pattern rather than a base type.
struct TransportBadgeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    /// See `TransportCircleButtonStyle.StyledLabel` — a `ButtonStyle` struct never receives
    /// environment updates itself, so the disabled read has to happen in a nested `View`.
    struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .opacity(isEnabled ? 1 : 0.45)
        }
    }
}
