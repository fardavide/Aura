import SwiftUI

/// The recordings transport, floated over the video on a glass bar: the instant under the playhead,
/// skip and play/pause, and the speed ladder. A pure function of `RecordingControlState`, so it
/// renders — and snapshots — without a player behind it.
public struct RecordingControlBar: View {
    private let state: RecordingControlState
    private let onPlayPause: () -> Void
    private let onSkip: (TimeInterval) -> Void
    private let onSelectSpeed: (PlaybackSpeed) -> Void

    public init(
        state: RecordingControlState,
        onPlayPause: @escaping () -> Void,
        onSkip: @escaping (TimeInterval) -> Void,
        onSelectSpeed: @escaping (PlaybackSpeed) -> Void
    ) {
        self.state = state
        self.onPlayPause = onPlayPause
        self.onSkip = onSkip
        self.onSelectSpeed = onSelectSpeed
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                clock
                Spacer()
                if !state.hasFootage {
                    Label("No footage", systemImage: "clock.badge.questionmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            HStack(spacing: 12) {
                skipButton(by: -10, systemImage: "gobackward.10")
                playPauseButton.disabled(!state.isPlayable)
                skipButton(by: 10, systemImage: "goforward.10")
                Spacer(minLength: 8)
                speedPicker.disabled(!state.isPlayable)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var clock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(state.instant, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            // Seconds are shown because the skip buttons move in ten of them.
            Text(state.instant, format: .dateTime.hour().minute().second())
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
    }

    private var playPauseButton: some View {
        Button(action: onPlayPause) {
            Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                .font(.title3)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
    }

    private func skipButton(by seconds: TimeInterval, systemImage: String) -> some View {
        Button {
            onSkip(seconds)
        } label: {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    private var speedPicker: some View {
        Picker("Speed", selection: Binding(get: { state.speed }, set: onSelectSpeed)) {
            ForEach(PlaybackSpeed.allCases, id: \.self) { speed in
                Text(speed.title).tag(speed)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 180)
    }
}
