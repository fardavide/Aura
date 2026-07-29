import SwiftUI
import Testing

import CamerasEntities
import TestDoubles
import TimelineDomain
import TimelinePresentation

/// Screenshot tests for the Timeline-detail screen. Recorded video never renders in a snapshot, so
/// `RecordingDetailLayout` is captured over a black placeholder: what's verified is the chrome —
/// the hero badges, the glass timeline panel with its day-overview bar, scrub track, ruler and
/// transport — in each of the three arrangements the device matrix produces (phone upright, phone
/// on its side, iPad), and that it all sits inside the safe area. The Hour-zoom filmstrip is
/// captured the same way network images can't render, so its store is given no material and the
/// strip degrades to its stable placeholder cells.
///
/// Driven by literal `RecordingDetailState`, so no `AVPlayer` and no server are involved.
@MainActor
struct RecordingPlayerSnapshotTests {

    @Test func `given a playing recording when the screen is shown then the timeline panel reads`() {
        // given
        let view = recordingDetail(state: detailState())

        // then
        assertScreenSnapshot(view, named: "detail")
    }

    @Test func `given a paused recording at eight times speed then the transport matches`() {
        // given
        let view = recordingDetail(state: detailState(isPlaying: false, speed: .eightX))

        // then
        assertScreenSnapshot(view, named: "detail-paused-8x")
    }

    @Test func `given the week zoom then the track covers more of the span`() {
        // given
        let view = recordingDetail(state: detailState(zoom: .week))

        // then
        assertScreenSnapshot(view, named: "detail-week")
    }

    @Test func `given the hour zoom then the filmstrip's placeholder slots line the track`() {
        // given
        let view = recordingDetail(state: detailState(zoom: .hour))

        // then
        assertScreenSnapshot(view, named: "detail-hour")
    }

    @Test func `given a playhead with nothing recorded then the hero says so`() {
        // given
        let view = recordingDetail(
            state: detailState(
                instant: snapshotSpanStart.addingTimeInterval(20 * 3600),
                timeline: gappyTimelineFixture(),
                hasFootage: false,
                isPlayable: false
            )
        )

        // then
        assertScreenSnapshot(view, named: "detail-no-footage")
    }

    @Test func `given the playhead parked at the live edge then the Live chip is prominent`() {
        // given
        let view = recordingDetail(state: detailState(instant: snapshotNow, isLive: true))

        // then
        assertScreenSnapshot(view, named: "detail-live")
    }

    @Test func `given area highlights then the surface and the initial camera slot are outlined`() {
        // given — diagnostics on: the outlined slot must never sit under the glass panel, and the
        // outlined surface shows how far zoomed footage may legitimately spill
        let view = recordingDetail(state: detailState())
            .environment(\.cameraAreaHighlights, true)

        // then
        assertScreenSnapshot(view, named: "detail-areas")
    }
}

// MARK: - View builder

@MainActor
private func recordingDetail(state: RecordingDetailState) -> some View {
    RecordingDetailLayout(state: state, actions: .inert, filmstrip: emptyFilmstrip()) {
        Color.black
    }
}

/// A store with nothing to load from — every filmstrip slot stays on its placeholder cell.
@MainActor
private func emptyFilmstrip() -> RecordingFilmstripStore {
    RecordingFilmstripStore(
        camera: CameraName("driveway"),
        previews: GetCameraPreviews(provider: FakeCameraPreviewProvider()),
        imageLoader: FakePreviewImageLoader()
    )
}

/// A playhead 33.4 hours into the two-day span — inside the rich fixture's busy stretch, with
/// markers on both sides of it so the jump buttons and the marker lane both have something to show.
private func detailState(
    instant: Date = snapshotSpanStart.addingTimeInterval(33.4 * 3600),
    timeline: DayTimeline = richTimelineFixture(),
    zoom: TimelineZoom = .day,
    isPlaying: Bool = true,
    speed: PlaybackSpeed = .oneX,
    hasFootage: Bool = true,
    isLive: Bool = false,
    isPlayable: Bool = true
) -> RecordingDetailState {
    RecordingDetailState(
        cameraName: "Driveway",
        instant: instant,
        span: TimeRange(start: snapshotSpanStart, end: snapshotNow),
        dayTimeline: timeline,
        zoom: zoom,
        isPlaying: isPlaying,
        speed: speed,
        hasFootage: hasFootage,
        isLive: isLive,
        isPlayable: isPlayable
    )
}
