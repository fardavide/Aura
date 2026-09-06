import SwiftUI

public enum AuroraBadgeTone: Sendable {
    /// Gradient fill, white ink — review alert (decision #10).
    case alert
    /// Amber fill, dark ink — review detection.
    case detection
    /// Live red, white ink — the "LIVE" solid badge on the timeline-detail hero.
    case live
    /// Outlined pink tag — text `AlertTagText` on `AlertTagFill`, border `AlertTagBorder` (Events rows, hero state pill).
    case alertTag
    /// Glass chip, primary ink — counts, labels.
    case neutral
}

public enum AuroraBadgeSize: Sendable {
    case compact   // 4 × 9 padding, `.livePill` type
    /// 3 × 8 padding, 11 / ExtraBold untracked — the video-frame identity badge (name + clock).
    case identity
    case regular   // 7 × 13 padding, `.captionEmphasis` type
}

extension View {
    public func auroraBadge(_ tone: AuroraBadgeTone, size: AuroraBadgeSize = .regular) -> some View {
        modifier(AuroraBadgeModifier(tone: tone, size: size))
    }
}

private struct AuroraBadgeModifier: ViewModifier {
    let tone: AuroraBadgeTone
    let size: AuroraBadgeSize

    func body(content: Content) -> some View {
        content
            .font(textFont)
            .tracking(size == .compact ? AuroraTextStyle.livePill.trackingEm * AuroraTextStyle.livePill.size : 0)
            .foregroundStyle(ink)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(fill, in: Capsule())
            .overlay { Capsule().strokeBorder(border, lineWidth: 1) }
    }

    private var textFont: Font {
        switch size {
        case .compact: .aurora(.livePill)
        case .identity: AuroraFonts.font(.extraBold, size: 11, relativeTo: .caption2)
        case .regular: .aurora(.captionEmphasis)
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .compact: 9
        case .identity: 8
        case .regular: 13
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .compact: 4
        case .identity: 3
        case .regular: 7
        }
    }

    private var fill: AnyShapeStyle {
        switch tone {
        case .alert: AnyShapeStyle(AuroraGradient.badge)
        case .detection: AnyShapeStyle(Color.auroraDetection.opacity(0.92))
        case .live: AnyShapeStyle(Color.auroraLive.opacity(0.9))
        case .alertTag: AnyShapeStyle(Color.auroraAlertTagFill)
        case .neutral: AnyShapeStyle(Color.auroraChipFill)
        }
    }

    private var ink: Color {
        switch tone {
        case .alert, .live: .white
        case .detection: .auroraDetectionInk
        case .alertTag: .auroraAlertTagText
        case .neutral: .auroraTextPrimary
        }
    }

    private var border: Color {
        switch tone {
        case .alert, .live, .detection: .white.opacity(0.18)
        case .alertTag: .auroraAlertTagBorder
        case .neutral: .auroraChipBorder
        }
    }
}
