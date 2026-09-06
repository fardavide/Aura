import Foundation
import Testing

import CamerasEntities
import TimelineDomain
@testable import TimelinePresentation

/// The two derived properties that let the transport's marker-jump buttons disable themselves at
/// the ends of the marker list, instead of pressing to nothing.
struct RecordingDetailStateTests {

    @Test func `given a playhead before every marker when asking for a previous marker then there is none`() {
        let state = detailState(instant: at(0), markers: [marker(at: 10)])
        #expect(state.hasPreviousMarker == false)
    }

    @Test func `given a playhead after the first marker when asking for a previous marker then there is one`() {
        let state = detailState(instant: at(20), markers: [marker(at: 10)])
        #expect(state.hasPreviousMarker)
    }

    @Test func `given a playhead after every marker when asking for a next marker then there is none`() {
        let state = detailState(instant: at(20), markers: [marker(at: 10)])
        #expect(state.hasNextMarker == false)
    }

    @Test func `given a playhead before the last marker when asking for a next marker then there is one`() {
        let state = detailState(instant: at(0), markers: [marker(at: 10)])
        #expect(state.hasNextMarker)
    }
}

// MARK: - Helpers

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private func marker(at seconds: TimeInterval) -> ReviewMarker {
    ReviewMarker(camera: CameraName("driveway"), start: at(seconds), end: at(seconds + 5), severity: .alert, label: "Person")
}

private func detailState(instant: Date, markers: [ReviewMarker]) -> RecordingDetailState {
    RecordingDetailState(
        cameraName: "Driveway",
        instant: instant,
        span: TimeRange(start: at(-1_000), end: at(1_000)),
        dayTimeline: DayTimeline(markers: markers, motion: [], gaps: []),
        zoom: .day,
        isPlaying: false,
        speed: .oneX,
        hasFootage: true,
        isLive: false,
        isPlayable: true
    )
}
