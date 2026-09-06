import SwiftUI

import CommonDesign

/// The transport's three circle sizes — jump, skip, play — as one glass-chip style built entirely
/// from `CommonDesign` tokens. Feature-internal on purpose: `CommonDesign`'s own gradient button
/// style is a *capsule* with its own padding and cannot render a 44pt circle (Risks R2).
struct TransportCircleButtonStyle: ButtonStyle {
    enum Role {
        /// The 30pt jump-to-marker buttons.
        case marker
        /// The 36pt ±10s skip buttons.
        case skip
        /// The 44pt play/pause button — gradient-filled with a pink glow.
        case play

        var diameter: CGFloat {
            switch self {
            case .marker: 30
            case .skip: 36
            case .play: 44
            }
        }

        var imageScale: Image.Scale {
            switch self {
            case .marker: .small
            case .skip: .medium
            case .play: .large
            }
        }
    }

    let role: Role

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(role: role, configuration: configuration)
    }

    /// A nested `View` so `@Environment(\.isEnabled)` actually updates — a `ButtonStyle` is not a
    /// `View`, so SwiftUI never injects the environment into properties stored directly on it. The
    /// play button is `.disabled(!state.isPlayable)` and this opacity is its only visual cue, so
    /// getting this wrong would ship a full-brightness button that swallows taps.
    struct StyledLabel: View {
        let role: Role
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .imageScale(role.imageScale)
                .foregroundStyle(role == .play ? .white : .auroraTextPrimary)
                .frame(width: role.diameter, height: role.diameter)
                .background {
                    Circle().fill(fill)
                }
                .overlay {
                    if role != .play {
                        Circle().strokeBorder(.auroraChipBorder, lineWidth: 1)
                    }
                }
                .shadow(color: role == .play ? .auroraGradientPink.opacity(0.8) : .clear, radius: 13, y: 6)
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .opacity(isEnabled ? 1 : 0.45)
        }

        private var fill: AnyShapeStyle {
            role == .play ? AnyShapeStyle(AuroraGradient.diagonal) : AnyShapeStyle(Color.auroraChipFill)
        }
    }
}
