import Foundation
import SwiftUI
import Testing

import CamerasEntities
import EventsDomain
import EventsPresentation
import TestDoubles

/// Screenshot tests for the pushed event detail screen. The clip player renders nothing
/// deterministic, so only the non-video states are captured; all show the header (label,
/// severity badge, camera, time · duration), and two cover the Frigate+ verdict panel. Wrapped in
/// a `NavigationStack` so the inline title bar and back chevron lay out as they do in the app.
@MainActor
struct EventDetailSnapshotTests {

    @Test func `given an event with no clip when shown then it matches the reference`() async {
        // given
        let view = await eventDetailScreen(event: snapshotEvent(hasClip: false), cameraName: "Front Door")

        // then
        assertScreenSnapshot(view, named: "no-clip")
    }

    @Test func `given a failing clip download when shown then it matches the reference`() async {
        // given
        let event = Event(
            id: EventId("evt-2"), camera: CameraName("driveway"), label: "car", severity: .detection,
            subLabel: nil, startTime: snapshotNow, endTime: snapshotNow.addingTimeInterval(65),
            hasClip: true, hasSnapshot: true, isObjectDetection: true, isSubmittedForTraining: false,
            score: 0.88, zones: []
        )
        let view = await eventDetailScreen(event: event, cameraName: "Driveway")

        // then
        assertScreenSnapshot(view, named: "failed")
    }

    @Test func `given a server that takes detection feedback when shown then the verdict panel matches the reference`() async {
        // given
        let view = await eventDetailScreen(
            event: snapshotEvent(hasClip: false), cameraName: "Front Door", feedbackEnabled: true
        )

        // then
        assertScreenSnapshot(view, named: "feedback")
    }

    @Test func `given an event already sent for training when shown then it points at Frigate Plus`() async {
        // given
        let view = await eventDetailScreen(
            event: snapshotEvent(hasClip: false, isSubmittedForTraining: true),
            cameraName: "Front Door",
            feedbackEnabled: true
        )

        // then
        assertScreenSnapshot(view, named: "feedback-submitted")
    }
}

// MARK: - Fixtures

private func snapshotEvent(hasClip: Bool, isSubmittedForTraining: Bool = false) -> Event {
    Event(
        id: EventId("evt-1"), camera: CameraName("front_door"), label: "person", severity: .alert,
        subLabel: nil, startTime: snapshotNow, endTime: snapshotNow.addingTimeInterval(42),
        hasClip: hasClip, hasSnapshot: true, isObjectDetection: true,
        isSubmittedForTraining: isSubmittedForTraining, score: 0.94, zones: ["porch"]
    )
}

// MARK: - View builder

/// Driven to its terminal states before rendering — including the feedback panel, whose own
/// `.task` returns early once it is no longer `.unavailable`, so the view's self-load settles on
/// the same pixels.
@MainActor
private func eventDetailScreen(
    event: Event,
    cameraName: String,
    feedbackEnabled: Bool = false
) async -> some View {
    let repository = FakeEventsRepository(.success([]), detectionFeedbackEnabled: .success(feedbackEnabled))
    let viewModel = EventDetailViewModel(
        event: event,
        clipLoader: FakeEventClipLoader(nil),
        isDetectionFeedbackEnabled: IsDetectionFeedbackEnabled(repository: repository),
        submitDetectionVerdict: SubmitDetectionVerdict(repository: repository)
    )
    await viewModel.load()
    await viewModel.loadFeedback()

    return NavigationStack {
        EventDetailView(viewModel: viewModel, cameraName: cameraName)
    }
}
