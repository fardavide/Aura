import Foundation
import Testing

import CamerasDomain
import CamerasEntities
import TestDoubles
import TimelineDomain

/// Screenshot tests for the timeline screen across its states, captured on every device +
/// orientation (iOS) and a fixed window (macOS). The Liquid-Glass scrubber card and the camera
/// grid are part of every `ready` snapshot.
@MainActor
struct TimelineScreenSnapshotTests {

    @Test func `given cameras and a busy day when ready then it matches the reference`() async {
        // given
        let view = await timelineScreen(cameras: .success(snapshotCameras()), timeline: .success(richTimelineFixture()))

        // then
        assertScreenSnapshot(view, named: "ready-busy")
    }

    @Test func `given cameras and a gappy day when ready then it matches the reference`() async {
        // given
        let view = await timelineScreen(cameras: .success(snapshotCameras()), timeline: .success(gappyTimelineFixture()))

        // then
        assertScreenSnapshot(view, named: "ready-gaps")
    }

    @Test func `given cameras and no activity when ready then it matches the reference`() async {
        // given
        let view = await timelineScreen(cameras: .success(snapshotCameras()), timeline: .success(quietTimelineFixture()))

        // then
        assertScreenSnapshot(view, named: "ready-quiet")
    }

    @Test func `given playback running when ready then it matches the reference`() async {
        // given — the transport running at 4×, so the card shows pause and the selected rung
        let view = await timelineScreen(
            cameras: .success(snapshotCameras()),
            timeline: .success(richTimelineFixture()),
            playing: true
        )

        // then
        assertScreenSnapshot(view, named: "ready-playing")
    }

    @Test func `given no cameras when empty then it matches the reference`() async {
        // given
        let view = await timelineScreen(cameras: .success([]), timeline: .success(quietTimelineFixture()))

        // then
        assertScreenSnapshot(view, named: "empty")
    }

    @Test func `given a server failure when failed then it matches the reference`() async {
        // given
        let view = await timelineScreen(cameras: .failure(.serverUnavailable), timeline: .success(quietTimelineFixture()))

        // then
        assertScreenSnapshot(view, named: "failed")
    }

    // The six states above settle every tile to `.unavailable` (no clips, no frames, no image), so
    // none of them photograph the footage-bearing chrome (scrim, name, clock, badge) or the hero
    // swap — this is the one state that does.
    @Test func `given an alerting camera when ready then it matches the reference`() async {
        // given — deterministic footage on every tile, plus an in-progress alert on front_door
        // (not the first camera), so the hero swap and the badge both render
        let previews = FakeCameraPreviewProvider(
            frames: [PreviewFrame(camera: CameraName("front_door"), time: snapshotNow, fileName: "preview_front_door-1.webp")]
        )
        let view = await timelineScreen(
            cameras: .success(snapshotCameras()),
            timeline: .success(heroAlertTimelineFixture()),
            previews: previews,
            imageLoader: FakePreviewImageLoader(image: solidPreviewPng)
        )

        // then
        assertScreenSnapshot(view, named: "ready-hero-alert")
    }

    @Test func `given a camera whose material fails to load when ready then it matches the reference`() async {
        // given — every tile's clips read fails, so `loadFromScratch` lands on `display = .failed`
        let previews = FakeCameraPreviewProvider()
        previews.clipsResult = .failure(.unreachable)
        let view = await timelineScreen(cameras: .success(snapshotCameras()), timeline: .success(quietTimelineFixture()), previews: previews)

        // then
        assertScreenSnapshot(view, named: "ready-tile-failed")
    }
}
