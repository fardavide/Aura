import SwiftUI
import Testing

import CommonPlayer

/// Screenshot tests for the live camera controls overlay. Live video never renders in a snapshot,
/// so the shared `LiveVideoLayout` is captured over a black placeholder: what's verified is that the
/// control chrome — the LIVE badge and the transport cluster — sits **inside** the safe area (not
/// under the status bar / notch) and that the button icons follow the state, across the device +
/// orientation matrix. Driven by literal `LiveControlState`, so no `AVPlayer` is built.
@MainActor
struct CameraDetailSnapshotTests {

    @Test func `given a playing stream when controls are shown then they sit inside the safe area`() {
        // given
        let view = liveControls(
            state: LiveControlState(
                isPlaying: true,
                isMuted: false,
                isPictureInPictureSupported: true,
                isPictureInPictureActive: false,
                isPictureInPicturePossible: true
            )
        )

        // then
        assertScreenSnapshot(view, named: "controls")
    }

    @Test func `given a paused muted stream in picture-in-picture then the control icons match`() {
        // given
        let view = liveControls(
            state: LiveControlState(
                isPlaying: false,
                isMuted: true,
                isPictureInPictureSupported: true,
                isPictureInPictureActive: true,
                isPictureInPicturePossible: true
            )
        )

        // then
        assertScreenSnapshot(view, named: "controls-paused-muted-pip")
    }
}

// MARK: - View builder

@MainActor
private func liveControls(state: LiveControlState) -> some View {
    LiveVideoLayout(
        controls: LiveControlBar(
            state: state,
            onPlayPause: {},
            onMute: {},
            onTogglePictureInPicture: {},
            onInteract: {}
        ),
        areControlsVisible: true,
        onSingleTap: {}
    ) {
        Color.black
    }
}
