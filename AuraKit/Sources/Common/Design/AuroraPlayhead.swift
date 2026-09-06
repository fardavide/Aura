import SwiftUI

public struct AuroraPlayhead: View {
    private let axis: Axis

    public init(axis: Axis) { self.axis = axis }

    public var body: some View {
        ZStack(alignment: axis == .horizontal ? .top : .leading) {
            Rectangle()
                .fill(LinearGradient(
                    gradient: AuroraGradient.playheadLineStops,
                    startPoint: axis == .horizontal ? .top : .leading,
                    endPoint: axis == .horizontal ? .bottom : .trailing
                ))
                .frame(width: axis == .horizontal ? AuroraTrack.playheadLineWidth : nil, height: axis == .vertical ? AuroraTrack.playheadLineWidth : nil)
            Circle()
                .fill(LinearGradient(gradient: AuroraGradient.playheadDotStops, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { Circle().strokeBorder(.white, lineWidth: AuroraTrack.playheadDotBorder) }
                .frame(width: AuroraTrack.playheadDotDiameter, height: AuroraTrack.playheadDotDiameter)
                .shadow(color: .auroraGradientPink.opacity(0.8), radius: 6)
                .offset(x: axis == .horizontal ? 0 : -3, y: axis == .horizontal ? -3 : 0)
        }
        .allowsHitTesting(false)
    }
}
