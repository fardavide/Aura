import SwiftUI

import CommonDesign

/// The export card's metrics, in one place because the list, the card and the snapshot tests all
/// measure against them.
enum ExportCardStyle {
    static let padding: CGFloat = 10
    /// Between the video frame and the identity block beside it.
    static let frameToIdentity: CGFloat = 11
    /// Between the two action circles.
    static let betweenActions: CGFloat = 6
    /// Between the card row and any state strip under it.
    static let rowToStrip: CGFloat = 9
    static let betweenCards: CGFloat = 8

    static let cornerRadius: CGFloat = 22
    static let frameCornerRadius: CGFloat = 13
    static let stripCornerRadius: CGFloat = 14
    static let progressCornerRadius: CGFloat = 3

    /// The 16:9 still in a list row. Full card width in the stacked layouts instead.
    static let frameSize = CGSize(width: 104, height: 59)
    /// The same still in a narrow split column — 32pt narrower, which is what the meta line needs
    /// to keep its time rather than truncating to "Jan 12,…".
    static let narrowFrameSize = CGSize(width: 72, height: 41)
    static let progressBarHeight: CGFloat = 6
    /// The server's indeterminate sweep, pinned to the card's top edge.
    static let sweepHeight: CGFloat = 3
    static let sweepDuration: TimeInterval = 1.6

    #if os(macOS)
    /// Pointer-only chrome; the whole card is a click target too.
    static let actionDiameter: CGFloat = 28
    #else
    static let actionDiameter: CGFloat = 44
    #endif

    /// The screen margin the list keeps either side of a card.
    static func screenMargin(horizontalSizeClass isRegular: Bool) -> CGFloat {
        #if os(macOS)
        return 20
        #else
        return isRegular ? 28 : 16
        #endif
    }
}

extension ShapeStyle where Self == Color {
    /// The disabled-control opacity the design pins for a processing card, as ink rather than a
    /// blanket `.opacity` — so the reason text beside it keeps full contrast.
    static var auroraDisabledInk: Color { .auroraTextPrimary.opacity(0.38) }
}
