import SwiftUI

extension View {
    /// A rounded-rect glass card (`SheetTint` fill, `SheetBorder` stroke, no grabber) — the
    /// surface an hour-group card, a camera tile or a Settings row group sits on. Distinct from
    /// `.auroraChip()` (a capsule) and `.auroraSheet(edge:)` (a flush-to-edge sheet with a
    /// grabber and glow).
    public func auroraCard(cornerRadius: CGFloat) -> some View {
        modifier(AuroraCardModifier(cornerRadius: cornerRadius))
    }
}

private struct AuroraCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular.tint(.auroraSheetTint), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.auroraSheetBorder, lineWidth: 1)
            }
    }
}
