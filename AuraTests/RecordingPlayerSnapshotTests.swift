import SwiftUI
import Testing

import TimelinePresentation

/// Screenshot tests for the recordings transport. Recorded video never renders in a snapshot, so
/// `RecordingPlayerLayout` is captured over a black placeholder: what's verified is that the glass
/// bar — the clock readout, the transport cluster and the speed ladder — sits **inside** the safe
/// area and that its icons and enablement follow the state, across the device + orientation matrix.
/// Driven by literal `RecordingControlState`, so no `AVPlayer` is built.
@MainActor
struct RecordingPlayerSnapshotTests {

    @Test func `given playing footage when controls are shown then they sit inside the safe area`() {
        // given
        let view = recordingControls(
            state: RecordingControlState(
                instant: snapshotNow,
                isPlaying: true,
                speed: .oneX,
                hasFootage: true,
                isPlayable: true
            )
        )

        // then
        assertScreenSnapshot(view, named: "controls")
    }

    @Test func `given a paused recording at eight times speed then the control icons match`() {
        // given
        let view = recordingControls(
            state: RecordingControlState(
                instant: snapshotNow,
                isPlaying: false,
                speed: .eightX,
                hasFootage: true,
                isPlayable: true
            )
        )

        // then
        assertScreenSnapshot(view, named: "controls-paused-8x")
    }

    @Test func `given an hour with no footage then the badge shows and playback is disabled`() {
        // given
        let view = recordingControls(
            state: RecordingControlState(
                instant: snapshotNow,
                isPlaying: false,
                speed: .oneX,
                hasFootage: false,
                isPlayable: false
            )
        )

        // then
        assertScreenSnapshot(view, named: "controls-no-footage")
    }
}

// MARK: - View builder

@MainActor
private func recordingControls(state: RecordingControlState) -> some View {
    RecordingPlayerLayout(
        controls: RecordingControlBar(
            state: state,
            onPlayPause: {},
            onSkip: { _ in },
            onSelectSpeed: { _ in }
        )
    ) {
        Color.black
    }
}
