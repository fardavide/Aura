import SwiftUI

import CommonDesign

/// How a `PreviewTileView` is chromed — one typed switch instead of four booleans threaded through
/// the tile. `.hero` is the compact grid's lead tile; `.compactGrid` its followers; `.regularGrid`
/// every tile on iPad/macOS and the landscape rail (a Max iPhone reports regular width in landscape,
/// so the style must key off this rather than the horizontal size class directly).
enum PreviewTileStyle: Sendable {
    case hero, compactGrid, regularGrid

    var cornerRadius: CGFloat {
        switch self {
        case .hero: 24
        case .compactGrid: 19
        case .regularGrid: 21
        }
    }

    var nameStyle: AuroraTextStyle {
        switch self {
        case .hero: .heroTitle
        case .compactGrid: .tileTitle
        // `.titleCompact` (17/ExtraBold) was requested but not added to CommonDesign; `.headline`
        // (17/Bold) is the plan's documented fallback — one weight lighter than the mock.
        case .regularGrid: .headline
        }
    }

    var showsClock: Bool {
        switch self {
        case .hero, .regularGrid: true
        case .compactGrid: false
        }
    }

    var chromeInset: CGFloat {
        switch self {
        case .hero, .regularGrid: 14
        case .compactGrid: 10
        }
    }

    /// Whether the "No footage"/"Unavailable" well shows the camera name — the mock's small tile
    /// well is text-only.
    var showsWellName: Bool {
        switch self {
        case .hero, .regularGrid: true
        case .compactGrid: false
        }
    }
}
