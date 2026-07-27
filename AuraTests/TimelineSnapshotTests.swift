import Testing

import CamerasDomain
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
}
