import SwiftUI

import CommonDesign

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
        /// A phone held upright: the mock's single row — cluster leading, speed chip and Live
        /// trailing — with a two-row fallback where even that can't fit.
        case compact
        /// The landscape rail: two short rows plus the Live pill, because five circles do not fit
        /// across 144 points.
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
            // Small controls on purpose — at regular size even a plain phone width can't hold
            // the row, and an overrun silently pushes the whole layout past the screen edges
            // (caught by the `detail-areas` highlight baseline). Where the row still can't fit
            // (a narrow split-view window, large Dynamic Type), it falls back to two rows
            // rather than letting controls run off-screen.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    previousMarkerButton
                    skipButton(by: -10, systemImage: "gobackward.10")
                    playPauseButton
                    skipButton(by: 10, systemImage: "goforward.10")
                    nextMarkerButton
                    // A trailing flexible frame, not a Spacer: a Spacer's ideal width is
                    // unbounded, which reads as "never fits" to the enclosing ViewThatFits.
                    HStack(spacing: 6) {
                        speedChip.fixedSize()
                        liveChip.fixedSize()
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        previousMarkerButton
                        skipButton(by: -10, systemImage: "gobackward.10")
                        playPauseButton
                        skipButton(by: 10, systemImage: "goforward.10")
                        nextMarkerButton
                    }
                    HStack(spacing: 8) {
                        speedChip
                        liveChip
                    }
                }
            }
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
                // The rail's only way back to live — without it there is no control here that
                // can leave a scrubbed-away hour (Dead-control audit).
                liveChip
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var playPauseButton: some View {
        Button(action: actions.playPause) {
            Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                // The play triangle reads off-centre in a circle; nudged right like the mock
                // (`margin-left:3px`, L160). Pause's two bars are already symmetric.
                .offset(x: state.isPlaying ? 0 : 1.5)
        }
        .buttonStyle(TransportCircleButtonStyle(role: .play))
        .disabled(!state.isPlayable)
        .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
    }

    private func skipButton(by seconds: TimeInterval, systemImage: String) -> some View {
        Button {
            actions.skip(seconds)
        } label: {
            Image(systemName: systemImage)
        }
        .buttonStyle(TransportCircleButtonStyle(role: .skip))
    }

    private var previousMarkerButton: some View {
        markerButton(
            systemImage: "backward.end.fill", label: "Previous activity",
            disabled: !state.hasPreviousMarker, action: actions.previousMarker
        )
    }

    private var nextMarkerButton: some View {
        markerButton(
            systemImage: "forward.end.fill", label: "Next activity",
            disabled: !state.hasNextMarker, action: actions.nextMarker
        )
    }

    private func markerButton(systemImage: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(TransportCircleButtonStyle(role: .marker))
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    /// R3/R16: the flat `.well` container avoids nesting a second `glassEffect` inside the sheet's
    /// own, and the full brand gradient (not the violet→pink badge gradient) is what the mock uses
    /// for a control that is itself the screen's primary action.
    private var speedLadder: some View {
        AuroraSegmentedControl(
            options: PlaybackSpeed.allCases,
            selection: Binding(get: { state.speed }, set: actions.selectSpeed),
            container: .well,
            selectedFill: .diagonal
        ) { $0.title }
        // `auroraText(.chip)` (Urbanist) carries no `tnum` (tokens §2.3 / R10) — restored here so
        // the rungs don't jitter as the selection cycles.
        .monospacedDigit()
        .disabled(!state.isPlayable)
    }

    private var speedChip: some View {
        Button {
            actions.selectSpeed(state.speed.next)
        } label: {
            Text(state.speed.title)
                .monospacedDigit()
                .frame(minWidth: 40)
                .auroraBadge(.neutral)
        }
        .buttonStyle(TransportBadgeButtonStyle())
        .disabled(!state.isPlayable)
        .accessibilityLabel("Playback speed")
        .accessibilityValue(state.speed.title)
    }

    /// Prominent — and red — only while the playhead is actually parked at the live edge, so it
    /// reads as a state as well as an action. Disabled while live: re-settling at the live edge is
    /// a press with no perceivable effect, and a badge label carries no press treatment of its own.
    private var liveChip: some View {
        Button(action: actions.goLive) {
            Text("Live")
                .frame(maxWidth: .infinity)
                .auroraBadge(state.isLive ? .live : .neutral)
                .shadow(color: state.isLive ? .auroraLive.opacity(0.5) : .clear, radius: 8)
        }
        .buttonStyle(TransportBadgeButtonStyle())
        .disabled(state.isLive)
        .accessibilityLabel("Go live")
        .accessibilityValue(state.isLive ? "Live" : "Behind live")
    }
}
