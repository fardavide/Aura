import SwiftUI

import CommonDesign

/// The card's circular actions. Glass at rest; the gradient and a 0.96 scale on press, so the
/// control visibly answers before anything else does.
///
/// A disabled circle dims its *ink* rather than the whole shape, because the reason printed beside
/// it must keep full contrast — the reason is the part that has to stay readable.
struct ExportActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(foreground(isPressed: configuration.isPressed))
            .frame(width: ExportCardStyle.actionDiameter, height: ExportCardStyle.actionDiameter)
            .background {
                if configuration.isPressed, isEnabled {
                    Circle().fill(AuroraGradient.diagonal)
                } else {
                    Circle().fill(.auroraChipFill)
                        .overlay { Circle().strokeBorder(.auroraChipBorder, lineWidth: 1) }
                }
            }
            .scaleEffect(configuration.isPressed && isEnabled ? 0.96 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(Circle())
    }

    private func foreground(isPressed: Bool) -> Color {
        guard isEnabled else { return .auroraDisabledInk }
        return isPressed ? .white : .auroraTextPrimary
    }
}
