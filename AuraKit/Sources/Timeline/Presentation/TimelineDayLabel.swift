import SwiftUI

import CommonDesign

/// The header's "Sun · 28 Jun" subtitle, beneath the "Timeline" title — the same title+subtitle
/// shape as the other two tabs. Isolated for the same reason `TimelineClockLabel` is: it observes
/// the clock, so the header's parent doesn't have to.
struct TimelineDayLabel: View {
    let clock: ScrubClock

    var body: some View {
        Text(clock.instant, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
            .auroraText(.captionEmphasis)
            .foregroundStyle(.auroraTextSecondary)
    }
}
