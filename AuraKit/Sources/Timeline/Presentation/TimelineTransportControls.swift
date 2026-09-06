import SwiftUI

import CommonDesign

/// The transport row on the scrubber card: skip, play/pause and the speed control.
///
/// `.stack` (iPhone) and `.row` (iPad/macOS) carry the full skip/play/skip set; `.row` also lays
/// out the segmented speed ladder underneath. `.rail` (the slim landscape card) has room for
/// play/pause and one speed button, so that button steps through the ladder instead of showing it.
/// Every control here is flat — one `glassEffect` per surface, and this row sits inside the
/// sheet's own glass.
struct TimelineTransportControls: View {
    let arrangement: TimelineCardArrangement
    let transport: TimelineTransport

    var body: some View {
        switch arrangement {
        case .stack:
            HStack(spacing: 8) {
                skipButton(by: -10, systemImage: "gobackward.10")
                playPauseButton
                skipButton(by: 10, systemImage: "goforward.10")
                Spacer(minLength: 8)
                speedPill
            }
        case .row:
            VStack(spacing: 10) {
                HStack(spacing: 9) {
                    skipButton(by: -10, systemImage: "gobackward.10")
                    playPauseButton
                    skipButton(by: 10, systemImage: "goforward.10")
                }
                speedLadder
            }
        case .rail:
            HStack(spacing: 10) {
                playPauseButton
                speedPill
            }
        }
    }

    private var playPauseDiameter: CGFloat {
        switch arrangement {
        case .stack: 48
        case .row: 50
        case .rail: 44
        }
    }

    private var playPauseButton: some View {
        Button { transport.togglePlayPause() } label: {
            Image(systemName: transport.isPlaying ? "pause.fill" : "play.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: playPauseDiameter, height: playPauseDiameter)
                .background(AuroraGradient.diagonal, in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1) }
                .shadow(color: .auroraGradientPink.opacity(0.55), radius: 13, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(transport.isPlaying ? "Pause" : "Play")
    }

    /// Built the same **flat** way as the play button, at a fixed 40pt, so the mock's 40/48/40
    /// hierarchy survives — `.buttonStyle(.glass)` pads *around* its label and would render larger
    /// than the 48pt play button, inverting the hierarchy.
    private func skipButton(by seconds: TimeInterval, systemImage: String) -> some View {
        Button { transport.skip(by: seconds) } label: {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.auroraTextPrimary)
                .frame(width: 40, height: 40)
                .background(.auroraChipFill, in: Circle())
                .overlay { Circle().strokeBorder(.auroraChipBorder, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seconds < 0 ? "Back 10 seconds" : "Forward 10 seconds")
    }

    /// The chip goes inside the label so the whole padded capsule hit-tests. Flat, not
    /// `.auroraChip` (always glass): this pill sits inside `.auroraSheet` — one glass layer per
    /// surface — so it is spelled inline from the chip's own catalog tokens instead.
    private var speedPill: some View {
        Button { transport.select(transport.speed.next) } label: {
            Text(transport.speed.title)
                .auroraNumerals(.rowSummary)
                .frame(minWidth: 56)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.auroraChipFill, in: Capsule())
                .overlay { Capsule().strokeBorder(.auroraChipBorder, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Speed")
        .accessibilityValue(transport.speed.title)
    }

    /// The design's speed ladder — every rung visible, the selected one picked out — rendered by
    /// `AuroraSegmentedControl` rather than a system segmented `Picker` (which cannot take a
    /// gradient selection). `container: .well` drops the control's own nested glass in favour of
    /// the recessed-well paint, since this sits inside the sheet's own glass.
    private var speedLadder: some View {
        // Both sides spelled as closures: handing the isolated `select` method to the control
        // directly crashes the 6.3.3 compiler in IRGen while thunking it.
        AuroraSegmentedControl(
            options: PlaybackSpeed.allCases,
            selection: Binding(get: { transport.speed }, set: { transport.select($0) }),
            container: .well
        ) { $0.title }
    }
}
