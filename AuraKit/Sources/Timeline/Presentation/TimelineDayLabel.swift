import SwiftUI

import CommonDesign

/// The iPad/macOS toolbar's "Sun · 28 Jun" beside the title. Isolated for the same reason
/// `TimelineClockLabel` is: it observes the clock, so the toolbar's parent doesn't have to.
struct TimelineDayLabel: View {
    let clock: ScrubClock

    var body: some View {
        Text(clock.instant, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
            .auroraText(.chip)
            .foregroundStyle(.auroraTextSecondary)
    }
}
