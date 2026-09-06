import SwiftUI

public enum AuroraTextStyle: Sendable, CaseIterable {
    case screenTitle      // 32 / ExtraBold / -0.03em  — tab titles
    case heroTitle        // 19 / ExtraBold / -0.01em  — live/timeline hero camera name
    case tileTitle        // 13 / ExtraBold             — camera tile name
    case headline         // 17 / Bold                  — event row title
    case body             // 15 / Medium
    case bodyEmphasis     // 15 / SemiBold
    case caption          // 12 / Medium
    case captionEmphasis  // 12 / SemiBold
    case overline         // 10.5 / Bold / +0.08em     — callers add .textCase(.uppercase)
    case sectionHeading   // 10.5 / Bold / +0.08em     — callers add .textCase(.uppercase) + .auroraTextQuaternary
    case chip             // 13 / Bold                  — segmented options, chips
    case button           // 15 / Bold                  — gradient action button label
    case livePill         // 10.5 / ExtraBold / +0.08em

    public var size: CGFloat {
        switch self {
        case .screenTitle: 32
        case .heroTitle: 19
        case .tileTitle: 13
        case .headline: 17
        case .body: 15
        case .bodyEmphasis: 15
        case .caption: 12
        case .captionEmphasis: 12
        case .overline: 10.5
        case .sectionHeading: 10.5
        case .chip: 13
        case .button: 15
        case .livePill: 10.5
        }
    }

    public var weight: AuroraFonts.Urbanist {
        switch self {
        case .screenTitle, .heroTitle, .tileTitle, .livePill: .extraBold
        case .headline, .overline, .sectionHeading, .chip, .button: .bold
        case .body, .caption: .medium
        case .bodyEmphasis, .captionEmphasis: .semiBold
        }
    }

    public var relativeTo: Font.TextStyle {
        switch self {
        case .screenTitle: .largeTitle
        case .heroTitle: .title3
        case .tileTitle, .chip: .footnote
        case .headline: .headline
        case .body, .bodyEmphasis, .button: .body
        case .caption, .captionEmphasis: .caption
        case .overline, .sectionHeading, .livePill: .caption2
        }
    }

    /// Em-relative tracking; `auroraText` multiplies by `size`.
    public var trackingEm: CGFloat {
        switch self {
        case .screenTitle: -0.03
        case .heroTitle: -0.01
        case .overline, .sectionHeading, .livePill: 0.08
        case .tileTitle, .headline, .body, .bodyEmphasis, .caption, .captionEmphasis, .chip, .button: 0
        }
    }
}

public enum AuroraNumeralStyle: Sendable, CaseIterable {
    case clockTab            // 34 / heavy  — Timeline tab clock
    case clockTabSeconds     // 16 / bold
    case clockDetail         // 31 / heavy  — Timeline detail clock
    case clockDetailSeconds  // 14 / bold
    case rowSummary          // 13 / bold   — camera grid summary counts
    case rulerLabel          // 10 / semibold — scrub-track ruler
    case axisLabel           // 9.5 / semibold — day-overview axis and histogram ruler (Canvas)

    public var size: CGFloat {
        switch self {
        case .clockTab: 34
        case .clockTabSeconds: 16
        case .clockDetail: 31
        case .clockDetailSeconds: 14
        case .rowSummary: 13
        case .rulerLabel: 10
        case .axisLabel: 9.5
        }
    }

    public var weight: Font.Weight {
        switch self {
        case .clockTab, .clockDetail: .heavy
        case .clockTabSeconds, .clockDetailSeconds, .rowSummary: .bold
        case .rulerLabel, .axisLabel: .semibold
        }
    }

    public var relativeTo: Font.TextStyle {
        switch self {
        case .clockTab, .clockDetail: .largeTitle
        case .clockTabSeconds: .callout
        case .clockDetailSeconds, .rowSummary: .footnote
        case .rulerLabel, .axisLabel: .caption2
        }
    }

    /// Clocks get -0.03em; labels 0.
    public var trackingEm: CGFloat {
        switch self {
        case .clockTab, .clockTabSeconds, .clockDetail, .clockDetailSeconds: -0.03
        case .rowSummary, .rulerLabel, .axisLabel: 0
        }
    }
}
