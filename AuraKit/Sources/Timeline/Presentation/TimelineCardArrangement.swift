import SwiftUI

import CommonDesign

/// How the scrubber card lays out its clock, histogram, transport and zoom control — three cases,
/// not a `Bool` pair, because the differences are not a single axis: `.row` also drops the legend
/// column layout, moves the zoom pill into the transport column, and fixes the clock to 190pt,
/// none of which follow from "is it horizontal".
///
/// `.stack` — compact width, regular height (iPhone portrait, narrow iPad split): clock over
/// histogram over transport, flush-bottom sheet, cycling speed pill.
/// `.row` — regular width (iPad, macOS): one row — clock column | histogram | transport + speed
/// ladder + zoom pill, flush-bottom sheet.
/// `.rail` — compact height (iPhone landscape): vertical histogram, flush-trailing sheet.
///
/// These three properties are the only spelling of the axis/edge/height mapping — no view
/// re-derives them inline.
enum TimelineCardArrangement: Sendable {
    case stack, row, rail

    var axis: Axis {
        switch self {
        case .stack, .row: .horizontal
        case .rail: .vertical
        }
    }

    /// The histogram's length along its cross axis — `nil` lets `.rail` fill the available height.
    var histogramLength: CGFloat? {
        switch self {
        case .stack: 60
        case .row: 72
        case .rail: nil
        }
    }

    var sheetEdge: AuroraSheetEdge {
        switch self {
        case .stack, .row: .bottom
        case .rail: .trailing
        }
    }
}
