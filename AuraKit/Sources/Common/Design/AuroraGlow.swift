import SwiftUI

public struct AuroraGlow: View {
    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                glow(.auroraWashViolet, at: UnitPoint(x: 0.25, y: 0.60), in: geo.size)
                glow(.auroraWashPink,   at: UnitPoint(x: 0.85, y: 0.30), in: geo.size)
                glow(.auroraWashBlue,   at: UnitPoint(x: 0.55, y: 0.95), in: geo.size)
            }
            .blur(radius: 28)
        }
        .allowsHitTesting(false)
    }

    private func glow(_ color: Color, at center: UnitPoint, in size: CGSize) -> some View {
        Circle().fill(color)
            .frame(width: size.width * 0.6, height: size.width * 0.6)
            .position(x: size.width * center.x, y: size.height * center.y)
    }
}
