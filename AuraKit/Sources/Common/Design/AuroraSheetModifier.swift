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

    /// Where the glass background stays pinned as it grows past the content's own bounds to
    /// reach `flushEdge` — the edge *opposite* `flushEdge` (see the modifier's doc comment).
    var backgroundAlignment: Alignment {
        switch self {
        case .bottom: .top
        case .trailing: .leading
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

    // `ignoresSafeArea` does not reposition a view sized by its own content (or by an explicit
    // frame, as `.rail` has) — verified empirically: a fixed-height view with `.ignoresSafeArea()`
    // applied directly stays exactly where safe-area-respecting layout already put it, floating
    // above a TabView's floating tab bar with a visible gap instead of sitting flush behind it
    // (the tab bar's reserved space is a `safeAreaInset`, not the window's own top/bottom insets,
    // and only a *background* layer's independent geometry can be told to disregard it). Only
    // `View.background(alignment:content:)` with `ignoresSafeArea` **inside** the closure reaches
    // the true edge, because that background is laid out independently of the foreground's size —
    // so the glass/border/glow go in the background, pinned at the edge opposite `flushEdge`
    // (`backgroundAlignment`) and free to grow past the foreground into the ignored safe area,
    // while the actual content stays put, safely inset from the bar.
    func body(content: Content) -> some View {
        let shape = edge.shape
        return VStack(spacing: 0) {
            if edge == .bottom, showsGrabber {
                Capsule().fill(.auroraGrabber).frame(width: 36, height: 5).padding(.top, 8).padding(.bottom, 10)
            }
            content
        }
        .background(alignment: edge.backgroundAlignment) {
            shape
                .fill(.clear)
                .glassEffect(.regular.tint(.auroraSheetTint), in: shape)
                .overlay { shape.strokeBorder(AuroraGradient.rim, lineWidth: 1) }
                .background { AuroraGlow().padding(-30) }
                .ignoresSafeArea(.container, edges: edge.flushEdge)
        }
    }
}
