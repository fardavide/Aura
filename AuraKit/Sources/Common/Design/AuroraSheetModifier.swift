import SwiftUI

public enum AuroraSheetEdge: Sendable {
    /// Flush with the bottom; rounded top corners. Phones, portrait iPad.
    case bottom
    /// Flush with the trailing edge; rounded leading corners. Landscape rail.
    case trailing

    var shape: UnevenRoundedRectangle {
        switch self {
        case .bottom:
            UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 30, style: .continuous)
        case .trailing:
            UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 30, bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous)
        }
    }

    var flushEdge: Edge.Set {
        switch self {
        case .bottom: .bottom
        case .trailing: .trailing
        }
    }
}

extension View {
    /// `showsGrabber` is false for a sheet that is not dismissable by drag (the Timeline tab's
    /// inline card) — a grabber advertises a drag that would do nothing.
    public func auroraSheet(edge: AuroraSheetEdge, showsGrabber: Bool = true) -> some View {
        modifier(AuroraSheetModifier(edge: edge, showsGrabber: showsGrabber))
    }

    /// The presented-sheet variant for `RootView`'s `.sheet` — the system sheet owns the shape,
    /// so this only sets presentation properties, plus the gradient rim and top sheen the system
    /// sheet does not draw.
    public func auroraSettingsSheet() -> some View {
        presentationBackground { Color.auroraSettingsSheet }
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                    .strokeBorder(AuroraGradient.rim, lineWidth: 1)
                    .ignoresSafeArea()
                Rectangle()
                    .fill(Color.auroraSheetBorder)
                    .frame(height: 1)
            }
    }
}

private struct AuroraSheetModifier: ViewModifier {
    let edge: AuroraSheetEdge
    let showsGrabber: Bool

    func body(content: Content) -> some View {
        let shape = edge.shape
        return VStack(spacing: 0) {
            if edge == .bottom, showsGrabber {
                Capsule().fill(.auroraGrabber).frame(width: 36, height: 5).padding(.top, 8).padding(.bottom, 10)
            }
            content
        }
        .glassEffect(.regular.tint(.auroraSheetTint), in: shape)
        .overlay { shape.strokeBorder(AuroraGradient.rim, lineWidth: 1) }
        .background { AuroraGlow().padding(-30) }
        .ignoresSafeArea(.container, edges: edge.flushEdge)
    }
}
