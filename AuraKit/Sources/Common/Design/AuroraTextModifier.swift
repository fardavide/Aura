import SwiftUI

extension View {
    public func auroraText(_ style: AuroraTextStyle) -> some View {
        font(.aurora(style)).tracking(style.trackingEm * style.size)
    }

    public func auroraNumerals(_ style: AuroraNumeralStyle) -> some View {
        modifier(AuroraNumeralModifier(style: style))
    }
}

private struct AuroraNumeralModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let style: AuroraNumeralStyle

    init(style: AuroraNumeralStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: style.weight, design: .rounded))
            .monospacedDigit()
            .tracking(style.trackingEm * size)
    }
}
