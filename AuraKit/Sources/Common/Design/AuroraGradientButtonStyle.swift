import SwiftUI

public struct AuroraGradientButtonStyle: ButtonStyle {
    public let glow: Bool

    public init(glow: Bool) { self.glow = glow }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .auroraText(.button)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(AuroraGradient.diagonal, in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1) }
            .shadow(color: glow ? Color.auroraGradientPink.opacity(0.5) : .clear, radius: 13, y: 6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AuroraGradientButtonStyle {
    public static var auroraGradient: AuroraGradientButtonStyle { .init(glow: false) }
    public static func auroraGradient(glow: Bool) -> AuroraGradientButtonStyle { .init(glow: glow) }
}
