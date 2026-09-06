import SwiftUI

public struct AuroraLivePill: View {
    public enum Style: Sendable {
        /// Dark glass, pink dot, 10.5/800 tracked label — camera tiles and the live stream bar.
        case glass
        /// Solid live red with glow — timeline-detail hero when at the live edge.
        case solid
    }

    @Environment(\.designMotion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false
    private let style: Style

    public init(style: Style) { self.style = style }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(style == .glass ? Color.auroraGradientPink : .white)
                .frame(width: 6, height: 6)
                .opacity(isDimmed ? 0.35 : 1)
            Text("LIVE").auroraText(.livePill)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(background, in: Capsule())
        .overlay { Capsule().strokeBorder(.auroraVideoChipBorder, lineWidth: 1) }
        .shadow(color: style == .solid ? Color.auroraLive.opacity(0.55) : .clear, radius: 10)
        .allowsHitTesting(false)
        .task {
            guard motion == .animated, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { isDimmed = true }
        }
    }

    private var background: AnyShapeStyle {
        switch style {
        case .glass: AnyShapeStyle(Color.auroraVideoChipFill)
        case .solid: AnyShapeStyle(Color.auroraLive.opacity(0.9))
        }
    }
}
