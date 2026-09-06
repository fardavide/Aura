import SwiftUI

public struct AuroraBackground: View {
    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.auroraBase
                wash(.auroraWashViolet, width: 0.70, height: 0.38, at: UnitPoint(x: 0.15, y: 0.00), in: geo.size)
                wash(.auroraWashPink,   width: 0.60, height: 0.34, at: UnitPoint(x: 0.92, y: 0.06), in: geo.size)
                wash(.auroraWashBlue,   width: 0.70, height: 0.40, at: UnitPoint(x: 0.55, y: 0.26), in: geo.size)
            }
        }
        .ignoresSafeArea()
    }

    private func wash(_ color: Color, width: CGFloat, height: CGFloat, at center: UnitPoint, in size: CGSize) -> some View {
        EllipticalGradient(colors: [color, .clear], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
            .frame(width: size.width * width * 2, height: size.height * height * 2)
            .position(x: size.width * center.x, y: size.height * center.y)
    }
}

extension View {
    /// Screen root: `.auroraBackground()` replaces `.background(Color(uiColor: .systemBackground))`
    /// and friends. Applied once per tab root; sheets and cards sit on top.
    public func auroraBackground() -> some View {
        background { AuroraBackground() }
    }
}
