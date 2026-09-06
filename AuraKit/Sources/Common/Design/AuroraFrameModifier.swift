import SwiftUI

extension View {
    /// Gradient-rimmed video frame (90° gradient, per spec). Clips to `cornerRadius - lineWidth`
    /// then pads by `lineWidth` and paints the gradient behind, so the rim is crisp at any scale
    /// and never covers pixels of the player. `borderOpacity` fades the rim only — the clip and
    /// padding stay put — for a zoomed card whose frame is dissolving into a full-bleed picture
    /// (`AuroraZoomChrome.borderOpacity`); the still-image call sites (camera tiles, event thumbs)
    /// never pass it and keep the frame fully opaque.
    public func auroraFrame(cornerRadius: CGFloat, lineWidth: CGFloat = 1.5, borderOpacity: Double = 1) -> some View {
        modifier(AuroraFrameModifier(cornerRadius: cornerRadius, lineWidth: lineWidth, borderOpacity: borderOpacity))
    }

    /// The soft violet card shadow behind a gradient-framed video card (mock: y 30, blur 60–100).
    public func auroraCardGlow(opacity: Double = 0.45) -> some View {
        shadow(color: .auroraWashViolet.opacity(opacity), radius: 60, y: 30)
    }
}

private struct AuroraFrameModifier: ViewModifier {
    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    let borderOpacity: Double

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius - lineWidth, style: .continuous))
            .padding(lineWidth)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AuroraGradient.vertical)
                    .opacity(borderOpacity)
            }
    }
}
