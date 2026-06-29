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
        assertTimelineSnapshot(view, named: "ready-busy")
    }

    @Test func `given cameras and a gappy day when ready then it matches the reference`() async {
        // given
        let view = await timelineScreen(cameras: .success(snapshotCameras()), timeline: .success(gappyTimelineFixture()))

        // then
        assertTimelineSnapshot(view, named: "ready-gaps")
    }

    @Test func `given cameras and no activity when ready then it matches the reference`() async {
        // given
        let view = await timelineScreen(cameras: .success(snapshotCameras()), timeline: .success(quietTimelineFixture()))

        // then
        assertTimelineSnapshot(view, named: "ready-quiet")
    }

    @Test func `given no cameras when empty then it matches the reference`() async {
        // given
        let view = await timelineScreen(cameras: .success([]), timeline: .success(quietTimelineFixture()))

        // then
        assertTimelineSnapshot(view, named: "empty")
    }

    @Test func `given a server failure when failed then it matches the reference`() async {
        // given
        let view = await timelineScreen(cameras: .failure(.serverUnavailable), timeline: .success(quietTimelineFixture()))

        // then
        assertTimelineSnapshot(view, named: "failed")
    }
}
