import Foundation
import SwiftUI
import Testing

import CamerasDomain
import EventsDomain
import EventsPresentation
import TestDoubles

/// Screenshot tests for the events list screen across its states, captured on every device +
/// orientation (iOS). Row thumbnails are pinned to the placeholder; event times are fixed
/// instants rendered through the pinned snapshot environment (POSIX locale, GMT).
@MainActor
struct EventsListSnapshotTests {

    @Test func `given events when loaded then it matches the reference`() async {
        // given
        let view = await eventsListScreen(events: .success(snapshotEvents()))

        // then
        assertScreenSnapshot(view, named: "loaded")
    }

    @Test func `given no events when empty then it matches the reference`() async {
        // given
        let view = await eventsListScreen(events: .success([]))

        // then
        assertScreenSnapshot(view, named: "empty")
    }

    @Test func `given a server failure when failed then it matches the reference`() async {
        // given
        let view = await eventsListScreen(events: .failure(.serverUnavailable))

        // then
        assertScreenSnapshot(view, named: "failed")
    }
}

// MARK: - Fixtures

/// A morning's worth of detections across the four snapshot cameras — distinct start times so
/// the newest-first ordering is stable, one still in progress (nil end), varied labels.
private func snapshotEvents() -> [Event] {
    func at(minutesAgo: Double) -> Date { snapshotNow.addingTimeInterval(-minutesAgo * 60) }

    return [
        Event(
            id: EventId("evt-1"), camera: CameraName("front_door"), label: "person",
            subLabel: nil, startTime: at(minutesAgo: 3), endTime: nil,
            hasClip: true, hasSnapshot: true, score: 0.94, zones: ["porch"]
        ),
        Event(
            id: EventId("evt-2"), camera: CameraName("driveway"), label: "car",
            subLabel: nil, startTime: at(minutesAgo: 22), endTime: at(minutesAgo: 21),
            hasClip: true, hasSnapshot: true, score: 0.88, zones: ["driveway"]
        ),
        Event(
            id: EventId("evt-3"), camera: CameraName("backyard"), label: "dog",
            subLabel: nil, startTime: at(minutesAgo: 65), endTime: at(minutesAgo: 63),
            hasClip: true, hasSnapshot: false, score: 0.71, zones: []
        ),
        Event(
            id: EventId("evt-4"), camera: CameraName("front_door"), label: "person",
            subLabel: "delivery", startTime: at(minutesAgo: 130), endTime: at(minutesAgo: 128),
            hasClip: false, hasSnapshot: true, score: 0.9, zones: ["porch"]
        ),
        Event(
            id: EventId("evt-5"), camera: CameraName("garage"), label: "cat",
            subLabel: nil, startTime: at(minutesAgo: 260), endTime: at(minutesAgo: 259),
            hasClip: true, hasSnapshot: true, score: nil, zones: []
        ),
        Event(
            id: EventId("evt-6"), camera: CameraName("driveway"), label: "car",
            subLabel: nil, startTime: at(minutesAgo: 1_500), endTime: at(minutesAgo: 1_495),
            hasClip: true, hasSnapshot: true, score: 0.82, zones: ["driveway"]
        ),
    ]
}

// MARK: - View builder

/// The events list screen, driven to a terminal state before rendering so the view's own
/// `.task` re-load settles on the same pixels. Thumbnails resolve to `nil`, pinning every row
/// to the deterministic placeholder.
@MainActor
private func eventsListScreen(events: Result<[Event], EventsError>) async -> some View {
    let viewModel = EventsListViewModel(
        getEvents: GetEvents(repository: FakeEventsRepository(events)),
        thumbnailLoader: FakeEventThumbnailLoader()
    )
    await viewModel.load()

    return EventsListView(
        viewModel: viewModel,
        onOpenSettings: {},
        // Unused: the detail factory is never invoked in a list snapshot (no navigation happens).
        makeDetailViewModel: { EventDetailViewModel(event: $0, clipLoader: FakeEventClipLoader()) }
    )
}
