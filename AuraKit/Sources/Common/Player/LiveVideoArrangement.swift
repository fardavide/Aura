import SwiftUI

import CommonDesign

/// Where the live picture sits, and therefore how everything around it behaves (decision #9):
/// a framed card on the aurora with the controls floating below it, or a full-bleed picture with
/// the controls overlaid on it (compact height).
public enum LiveVideoArrangement: Equatable, Sendable {
    case card
    case fill

    /// `nil` (macOS, where there is no size class) means a card, like any regular height.
    public init(verticalSizeClass: UserInterfaceSizeClass?) {
        self = verticalSizeClass == .compact ? .fill : .card
    }

    /// Controls that float *below* the picture never need to get out of the way; controls that
    /// sit *on* it do.
    public var autoHidesControls: Bool {
        switch self {
        case .card: false
        case .fill: true
        }
    }

    /// The card's pill floats on the aurora background, so it follows the appearance; the
    /// full-bleed one sits on footage, so it stays dark in both (decision #11).
    public var controlSurface: AuroraGlassSurface {
        switch self {
        case .card: .chrome
        case .fill: .video
        }
    }

    /// Mock L84 for the card; 20 is today's `LiveControlBar` inset, kept for `.fill`.
    public var controlsBottomInset: CGFloat {
        switch self {
        case .card: 28
        case .fill: 20
        }
    }

    public var videoIgnoredEdges: Edge.Set {
        switch self {
        case .card: []
        case .fill: .all
        }
    }

    /// `canvas` is the region *above* the control band (the controls are a bottom safe-area
    /// inset), so a card can never be sized into them.
    public func metrics(canvas: CGSize) -> LiveVideoMetrics {
        switch self {
        case .card:
            let width = max(0, min(canvas.width - 32, canvas.height * 16 / 9))   // 16 pt each side
            let height = width * 9 / 16
            return LiveVideoMetrics(
                videoSize: CGSize(width: width, height: height),
                videoCornerRadius: 22,
                videoRimWidth: 1.5,
                cardGlowOpacity: 1,
                livePillInset: CGPoint(
                    x: (canvas.width - width) / 2 + 14,     // mock L81: 14 inside the card
                    y: (canvas.height - height) / 2 + 14
                )
            )
        case .fill:
            return LiveVideoMetrics(
                videoSize: nil,
                videoCornerRadius: 0,
                videoRimWidth: 0,
                cardGlowOpacity: 0,
                livePillInset: CGPoint(x: 20, y: 20)        // today's `.padding(20)`
            )
        }
    }
}

/// Everything `LiveVideoLayout` needs to place its three children, as plain numbers.
public struct LiveVideoMetrics: Equatable, Sendable {
    /// `nil` = stay flexible; handed straight to `frame(width:height:)`, whose parameters are
    /// optional for exactly this reason.
    public let videoSize: CGSize?
    public let videoCornerRadius: CGFloat
    public let videoRimWidth: CGFloat
    public let cardGlowOpacity: Double
    /// Leading / top inset of the LIVE pill from the canvas' top-leading corner.
    public let livePillInset: CGPoint

    public init(
        videoSize: CGSize?,
        videoCornerRadius: CGFloat,
        videoRimWidth: CGFloat,
        cardGlowOpacity: Double,
        livePillInset: CGPoint
    ) {
        self.videoSize = videoSize
        self.videoCornerRadius = videoCornerRadius
        self.videoRimWidth = videoRimWidth
        self.cardGlowOpacity = cardGlowOpacity
        self.livePillInset = livePillInset
    }
}
