import SwiftUI
import Testing

import CamerasDomain
import CamerasEntities
import CamerasPresentation
import CommonPlayer
import TestDoubles

/// Screenshot tests for the live camera screen. `.card` (regular height) verifies the video is a
/// framed 16:9 card floating on the aurora background with the transport pill below it; `.fill`
/// (compact height) verifies the chrome still sits inside the safe area, overlaid on a full-bleed
/// picture — unchanged from before the restyle. Live video never renders in a snapshot: the
/// controls states are captured with `LiveVideoLayout` over a black placeholder, driven by literal
/// `LiveControlState`, so no `AVPlayer` is built; the `no-stream` state renders the real
/// `CameraDetailView` in its `.unavailable` branch, which is equally deterministic.
@MainActor
struct CameraDetailSnapshotTests {

    @Test func `given a playing stream when the card layout is shown then the video is framed and the controls float below`() {
        // given
        let view = liveControls(
            arrangement: .card,
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
            arrangement: .card,
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

    @Test func `given compact height when the layout is shown then the video fills and the controls overlay it`() {
        // given — pins that iPhone-landscape behaviour did not change
        let view = liveControls(
            arrangement: .fill,
            state: LiveControlState(
                isPlaying: true,
                isMuted: false,
                isPictureInPictureSupported: true,
                isPictureInPictureActive: false,
                isPictureInPicturePossible: true
            )
        )

        // then
        assertScreenSnapshot(view, named: "controls-compact")
    }

    @Test func `given a camera with no live stream when the detail screen is shown then it explains and still offers the timeline`() {
        // given — no `AVPlayer` is ever built: the view model resolves straight to `.unavailable`
        let view = cameraDetail(streamed: nil)

        // then
        assertScreenSnapshot(view, named: "no-stream")
    }
}

// MARK: - View builders

@MainActor
private func liveControls(arrangement: LiveVideoArrangement, state: LiveControlState) -> some View {
    LiveVideoLayout(
        arrangement: arrangement,
        controls: LiveControlBar(
            state: state,
            surface: arrangement.controlSurface,
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

/// The full `CameraDetailView`, with a stub `navigationDestination` registered for
/// `CameraTimelineRoute` — without it, a value-based `NavigationLink` whose type has no destination
/// in scope renders **disabled**, which would bake a greyed-out, inoperable Timeline button into
/// the `no-stream` baselines.
@MainActor
private func cameraDetail(streamed: CameraStreamSource?) -> some View {
    let camera = Camera(
        name: CameraName("front_door"), friendlyName: "Front Door", isEnabled: true, streamNames: ["front_door"]
    )
    let viewModel = CameraDetailViewModel(camera: camera, streamProvider: FakeCameraStreamProvider(streamed))

    return NavigationStack {
        CameraDetailView(camera: camera, viewModel: viewModel)
    }
    .navigationDestination(for: CameraTimelineRoute.self) { _ in Color.clear }
}
