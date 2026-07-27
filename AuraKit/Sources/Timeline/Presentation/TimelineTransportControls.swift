import SwiftUI

/// The transport row on the scrubber card: skip, play/pause and the speed ladder.
///
/// The wide card carries the full set — ten seconds either way and every rung of the ladder laid
/// out. The slim landscape card has room for play/pause and one speed button, so that button steps
/// through the ladder instead of showing it.
struct TimelineTransportControls: View {
    let axis: Axis
    let transport: TimelineTransport

    var body: some View {
        switch axis {
        case .horizontal:
            HStack(spacing: 12) {
                skipButton(by: -10, systemImage: "gobackward.10")
                playPauseButton
                skipButton(by: 10, systemImage: "goforward.10")
                Spacer(minLength: 8)
                speedPicker
            }
        case .vertical:
            HStack(spacing: 10) {
                playPauseButton
                Button { transport.select(transport.speed.next) } label: {
                    Text(transport.speed.title)
                        .font(.footnote.weight(.bold))
                        .monospacedDigit()
                        // A fixed slot so stepping the ladder doesn't resize the chip under the
                        // finger that is tapping it.
                        .frame(minWidth: 26)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Speed")
                .accessibilityValue(transport.speed.title)
            }
        }
    }

    private var playPauseButton: some View {
        Button { transport.togglePlayPause() } label: {
            Image(systemName: transport.isPlaying ? "pause.fill" : "play.fill")
                .font(.title3)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .accessibilityLabel(transport.isPlaying ? "Pause" : "Play")
    }

    private func skipButton(by seconds: TimeInterval, systemImage: String) -> some View {
        Button { transport.skip(by: seconds) } label: {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    /// The design's speed ladder — every rung visible, the selected one picked out — rendered by the
    /// system segmented picker rather than a hand-built row of chips. Tinted because the default
    /// selection is a pale capsule that all but disappears against the glass card behind it.
    private var speedPicker: some View {
        // Both sides spelled as closures: handing the picker the isolated `select` method directly
        // crashes the 6.3.3 compiler in IRGen while thunking it.
        Picker("Speed", selection: Binding(get: { transport.speed }, set: { transport.select($0) })) {
            ForEach(PlaybackSpeed.allCases, id: \.self) { speed in
                Text(speed.title)
                    .font(.footnote.weight(.bold))
                    .monospacedDigit()
                    .tag(speed)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}
