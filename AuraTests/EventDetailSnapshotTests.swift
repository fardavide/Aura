import Foundation
import SwiftUI
import Testing

import CamerasEntities
import EventsDomain
import EventsPresentation
import TestDoubles

/// Screenshot tests for the pushed event detail screen. The clip player renders nothing
/// deterministic, so only the two non-video states are captured; both show the new header (label,
/// severity badge, camera, time · duration), which is the point of this suite. Wrapped in a
/// `NavigationStack` so the inline title bar and back chevron lay out as they do in the app.
@MainActor
struct EventDetailSnapshotTests {

    @Test func `given an event with no clip when shown then it matches the reference`() async {
        // given
        let event = Event(
            id: EventId("evt-1"), camera: CameraName("front_door"), label: "person", severity: .alert,
            subLabel: nil, startTime: snapshotNow, endTime: snapshotNow.addingTimeInterval(42),
            hasClip: false, hasSnapshot: true, score: 0.94, zones: ["porch"]
        )
        let view = await eventDetailScreen(event: event, cameraName: "Front Door", clip: FakeEventClipLoader(nil))

        // then
        assertScreenSnapshot(view, named: "no-clip")
    }

    @Test func `given a failing clip download when shown then it matches the reference`() async {
        // given
        let event = Event(
            id: EventId("evt-2"), camera: CameraName("driveway"), label: "car", severity: .detection,
            subLabel: nil, startTime: snapshotNow, endTime: snapshotNow.addingTimeInterval(65),
            hasClip: true, hasSnapshot: true, score: 0.88, zones: []
        )
        let view = await eventDetailScreen(event: event, cameraName: "Driveway", clip: FakeEventClipLoader(nil))

        // then
        assertScreenSnapshot(view, named: "failed")
    }
}

// MARK: - View builder

@MainActor
private func eventDetailScreen(event: Event, cameraName: String, clip: FakeEventClipLoader) async -> some View {
    let viewModel = EventDetailViewModel(event: event, clipLoader: clip)
    await viewModel.load()

    return NavigationStack {
        EventDetailView(viewModel: viewModel, cameraName: cameraName)
    }
}
