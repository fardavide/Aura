import SwiftUI

import CommonDesign

/// The zoomable video screens' decorative border rim. Unlike `auroraFrame`, this never clips or
/// insets the content it's laid over: the picture is meant to grow past it, unbound, as the zoom
/// transform scales up (`AuroraZoomChrome`'s whole point), so the rim can only be a floating
/// overlay — sized once to the card's rest dimensions and left there while its opacity fades,
/// never resizing itself (a zoomed-in picture doesn't drag its frame bigger with it).
public struct AuroraZoomFrame: View {
    private let cornerRadius: CGFloat
    private let lineWidth: CGFloat
    private let opacity: Double

    public init(cornerRadius: CGFloat, lineWidth: CGFloat, opacity: Double) {
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
        self.opacity = opacity
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(AuroraGradient.vertical, lineWidth: lineWidth)
            .opacity(opacity)
    }
}
