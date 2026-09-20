import SwiftUI

import CommonDesign
import EventsDomain

extension DetectionVerdict {
    var iconSystemName: String {
        switch self {
        case .correct: "checkmark.circle.fill"
        case .incorrect: "xmark.circle.fill"
        }
    }
}

extension View {

    /// How a label reads once the user has told Frigate+ it was wrong: struck through and dropped
    /// to `TextMuted` — the one token that sits furthest back in **both** schemes (`#8C87A8` light,
    /// `#7C7896` dark; the ramp is otherwise monotonic per scheme, so `TextTertiary`/`TextQuaternary`
    /// invert between them and only `TextMuted` recedes either way).
    ///
    /// Pair with `DetectionVerdictIcon` placed before the label — colour and a strikethrough alone
    /// read as merely dimmed at a glance (confirmed against a live comparison of four treatments);
    /// the icon is what actually breaks the scan pattern.
    ///
    /// Untouched when the label stands, so a row with no verdict keeps inheriting its colour.
    @ViewBuilder func reportedWrong(_ isReportedWrong: Bool) -> some View {
        if isReportedWrong {
            strikethrough(color: .auroraTextMuted).foregroundStyle(.auroraTextMuted)
        } else {
            self
        }
    }
}

/// The fixed-width glyph placed before a label once its verdict is on record. Sized independently
/// of the label's font, unlike the old "NOT A …" text badge — that one scaled with the label and
/// wrapped a long word ("Motorcycle") across the row, the severity tag and itself all at once.
/// Purely decorative: the event screen's panel carries the verdict's meaning for VoiceOver.
struct DetectionVerdictIcon: View {
    let verdict: DetectionVerdict

    var body: some View {
        Image(systemName: verdict.iconSystemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(verdict == .correct ? .auroraGradientBlue : .auroraTextMuted)
            .accessibilityHidden(true)
    }
}
