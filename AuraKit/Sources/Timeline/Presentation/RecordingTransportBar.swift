import SwiftUI

/// The transport for one camera's recordings: jump to the previous activity, ten seconds back,
/// play/pause, ten seconds on, jump to the next activity — plus the speed ladder and the Live chip.
///
/// The speed ladder stays the mock's segmented control wherever there is room for it, and becomes a
/// chip cycling the same four rungs where there isn't, so the affordance survives the narrow
/// layouts instead of being swapped for a menu. `density` says how much room there is; nothing
/// here reads the size classes itself.
struct RecordingTransportBar: View {
    enum Density {
        /// The wide panel's control column: the whole cluster on one row, speed as a ladder.
        case wide
        /// A phone held upright: one row — the cluster leading, speed chip and Live trailing.
        case compact
        /// The landscape rail: two short rows, because five circles do not fit across 144 points.
        case narrow
    }

    let state: RecordingDetailState
    let actions: RecordingDetailActions
    let density: Density

    var body: some View {
        switch density {
        case .wide:
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    previousMarkerButton
                    skipButton(by: -10, systemImage: "gobackward.10")
                    playPauseButton
                    skipButton(by: 10, systemImage: "goforward.10")
                    nextMarkerButton
                }
                HStack(spacing: 8) {
                    speedLadder
                    liveChip
                }
            }
        case .compact:
            // The mock's single row: the transport cluster leading, speed and Live trailing.
            // Small controls on purpose — at regular size the row's minimum width overruns a
            // phone and silently pushes the whole layout past the screen edges (caught by the
            // `detail-areas` highlight baseline).
            HStack(spacing: 6) {
                previousMarkerButton
                skipButton(by: -10, systemImage: "gobackward.10")
                playPauseButton
                skipButton(by: 10, systemImage: "goforward.10")
                nextMarkerButton
                Spacer(minLength: 4)
                speedChip.fixedSize()
                liveChip.fixedSize()
            }
            .controlSize(.small)
        case .narrow:
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    skipButton(by: -10, systemImage: "gobackward.10")
                    playPauseButton
                    skipButton(by: 10, systemImage: "goforward.10")
                }
                HStack(spacing: 6) {
                    previousMarkerButton
                    speedChip
                    nextMarkerButton
                }
            }
        }
    }

    private var playPauseButton: some View {
        Button(action: actions.playPause) {
            Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                .font(.title3)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .disabled(!state.isPlayable)
        .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
    }

    private func skipButton(by seconds: TimeInterval, systemImage: String) -> some View {
        Button {
            actions.skip(seconds)
        } label: {
            Image(systemName: systemImage)
                .font(.body)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    private var previousMarkerButton: some View {
        markerButton(systemImage: "backward.end.fill", label: "Previous activity", action: actions.previousMarker)
    }

    private var nextMarkerButton: some View {
        markerButton(systemImage: "forward.end.fill", label: "Next activity", action: actions.nextMarker)
    }

    private func markerButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
    }

    private var speedLadder: some View {
        Picker("Speed", selection: Binding(get: { state.speed }, set: actions.selectSpeed)) {
            ForEach(PlaybackSpeed.allCases, id: \.self) { speed in
                Text(speed.title).tag(speed)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // The stock segmented picker washes out over the glass panel; bolder reads closer to the
        // mock's ladder and stays legible against it.
        .font(.footnote.weight(.bold))
        .disabled(!state.isPlayable)
    }

    private var speedChip: some View {
        Button {
            actions.selectSpeed(state.speed.next)
        } label: {
            Text(state.speed.title)
                .font(.footnote.weight(.bold))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .disabled(!state.isPlayable)
        .accessibilityLabel("Playback speed")
        .accessibilityValue(state.speed.title)
    }

    /// Prominent — and red — only while the playhead is actually parked at the live edge, so it
    /// reads as a state as well as an action.
    @ViewBuilder private var liveChip: some View {
        let label = Text("Live").font(.footnote.weight(.bold)).frame(maxWidth: .infinity)
        if state.isLive {
            Button(action: actions.goLive) { label }
                .buttonStyle(.glassProminent)
                .tint(.red)
        } else {
            Button(action: actions.goLive) { label }
                .buttonStyle(.glass)
        }
    }
}
