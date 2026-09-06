import SwiftUI
import Testing

@testable import CommonDesign

@Suite
struct AuroraTextStyleTests {
    @Test
    func `given every text style when reading metrics then size weight relativeTo and tracking match the spec table`() {
        for expected in Scenario.textStyles {
            let style = expected.style
            #expect(style.size == expected.size)
            #expect(style.weight == expected.weight)
            #expect(style.relativeTo == expected.relativeTo)
            #expect(style.trackingEm == expected.trackingEm)
        }
    }

    @Test
    func `given every numeral style when reading metrics then size weight relativeTo and tracking match the spec table`() {
        for expected in Scenario.numeralStyles {
            let style = expected.style
            #expect(style.size == expected.size)
            #expect(style.weight == expected.weight)
            #expect(style.relativeTo == expected.relativeTo)
            #expect(style.trackingEm == expected.trackingEm)
        }
    }
}

private struct TextExpectation {
    let style: AuroraTextStyle
    let size: CGFloat
    let weight: AuroraFonts.Urbanist
    let relativeTo: Font.TextStyle
    let trackingEm: CGFloat
}

private struct NumeralExpectation {
    let style: AuroraNumeralStyle
    let size: CGFloat
    let weight: Font.Weight
    let relativeTo: Font.TextStyle
    let trackingEm: CGFloat
}

private enum Scenario {
    static let textStyles: [TextExpectation] = [
        TextExpectation(style: .screenTitle, size: 32, weight: .extraBold, relativeTo: .largeTitle, trackingEm: -0.03),
        TextExpectation(style: .heroTitle, size: 19, weight: .extraBold, relativeTo: .title3, trackingEm: -0.01),
        TextExpectation(style: .tileTitle, size: 13, weight: .extraBold, relativeTo: .footnote, trackingEm: 0),
        TextExpectation(style: .headline, size: 17, weight: .bold, relativeTo: .headline, trackingEm: 0),
        TextExpectation(style: .body, size: 15, weight: .medium, relativeTo: .body, trackingEm: 0),
        TextExpectation(style: .bodyEmphasis, size: 15, weight: .semiBold, relativeTo: .body, trackingEm: 0),
        TextExpectation(style: .caption, size: 12, weight: .medium, relativeTo: .caption, trackingEm: 0),
        TextExpectation(style: .captionEmphasis, size: 12, weight: .semiBold, relativeTo: .caption, trackingEm: 0),
        TextExpectation(style: .overline, size: 10.5, weight: .bold, relativeTo: .caption2, trackingEm: 0.08),
        TextExpectation(style: .sectionHeading, size: 10.5, weight: .bold, relativeTo: .caption2, trackingEm: 0.08),
        TextExpectation(style: .chip, size: 13, weight: .bold, relativeTo: .footnote, trackingEm: 0),
        TextExpectation(style: .button, size: 15, weight: .bold, relativeTo: .body, trackingEm: 0),
        TextExpectation(style: .livePill, size: 10.5, weight: .extraBold, relativeTo: .caption2, trackingEm: 0.08),
    ]

    static let numeralStyles: [NumeralExpectation] = [
        NumeralExpectation(style: .clockTab, size: 34, weight: .heavy, relativeTo: .largeTitle, trackingEm: -0.03),
        NumeralExpectation(style: .clockTabSeconds, size: 16, weight: .bold, relativeTo: .callout, trackingEm: -0.03),
        NumeralExpectation(style: .clockDetail, size: 31, weight: .heavy, relativeTo: .largeTitle, trackingEm: -0.03),
        NumeralExpectation(style: .clockDetailSeconds, size: 14, weight: .bold, relativeTo: .footnote, trackingEm: -0.03),
        NumeralExpectation(style: .rowSummary, size: 13, weight: .bold, relativeTo: .footnote, trackingEm: 0),
        NumeralExpectation(style: .rulerLabel, size: 10, weight: .semibold, relativeTo: .caption2, trackingEm: 0),
        NumeralExpectation(style: .axisLabel, size: 9.5, weight: .semibold, relativeTo: .caption2, trackingEm: 0),
    ]
}
