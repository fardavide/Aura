import SwiftUI

import CommonDesign

extension View {

    /// How a label reads once the user has told Frigate+ it was wrong: struck through and dropped to
    /// muted ink, so the row recedes like a crossed-off item.
    ///
    /// A "NOT A …" badge shipped here first and had to go: a long label ("Motorcycle") left the row
    /// no width for one, so the badge, the severity tag *and* the label all wrapped mid-word. The
    /// meaning it carried is stated in full on the event screen's panel instead, which has the room.
    ///
    /// The ink is `TextMuted`, the one token that sits furthest back in **both** schemes
    /// (`#8C87A8` light, `#7C7896` dark). `TextTertiary` shipped here first and read as barely
    /// dimmed: at `#5F5A7C` against a `#1A1630` primary it is only a shade off a normal label,
    /// which left the strikethrough doing all the work on its own.
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
