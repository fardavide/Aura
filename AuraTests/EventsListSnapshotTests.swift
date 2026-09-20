import Foundation
import SwiftUI
import Testing

import CamerasDomain
import CamerasEntities
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

    @Test func `given no alerts when loaded then the hero reads latest event`() async {
        // given
        let view = await eventsListScreen(events: .success(snapshotDetections()))

        // then
        assertScreenSnapshot(view, named: "detections-only")
    }

    @Test func `given a verified event when loaded then its indicator matches the reference`() async {
        // given
        let view = await eventsListScreen(events: .success(snapshotVerifiedEvent()))

        // then
        assertScreenSnapshot(view, named: "verified")
    }

    @Test func `given a label filter when selected then only that label is shown`() async {
        // given
        let view = await eventsListScreen(events: .success(snapshotEvents()), filter: .label("person"))

        // then
        assertScreenSnapshot(view, named: "filtered")
    }

    @Test func `given no camera names when loaded then rows fall back to the slug`() async {
        // given
        let view = await eventsListScreen(events: .success(snapshotEvents()), cameras: .failure(.unreachable))

        // then
        assertScreenSnapshot(view, named: "no-cameras")
    }
}

// MARK: - Fixtures

/// A morning's worth of events across the four snapshot cameras — distinct start times so the
/// newest-first ordering is stable, one still in progress (nil end), varied labels. Exercises the
/// hero ("LATEST ALERT" on `evt-2`), a ringed row, an ALERT tag, an in-progress row with no
/// duration, several hour groups, a day boundary the subtitle must exclude, four chips, and — on
/// `evt-3` — the longest label a row has to survive, already reported wrong (struck through,
/// muted, with its leading icon) and severity-tagged, all in the same row.
private func snapshotEvents() -> [Event] {
    func at(minutesAgo: Double) -> Date { snapshotNow.addingTimeInterval(-minutesAgo * 60) }

    return [
        Event(
            id: EventId("evt-1"), camera: CameraName("front_door"), label: "person", severity: .detection,
            subLabel: nil, startTime: at(minutesAgo: 3), endTime: nil,
            hasClip: true, hasSnapshot: true, isObjectDetection: true, verdict: nil,
            score: 0.94, zones: ["porch"]
        ),
        Event(
            id: EventId("evt-2"), camera: CameraName("driveway"), label: "car", severity: .alert,
            subLabel: nil, startTime: at(minutesAgo: 22), endTime: at(minutesAgo: 21),
            hasClip: true, hasSnapshot: true, isObjectDetection: true, verdict: nil,
            score: 0.88, zones: ["driveway"]
        ),
        Event(
            // The longest label a row has to survive, reported wrong and severity-tagged: the
            // combination that used to wrap the label, the tag and a badge all mid-word.
            id: EventId("evt-3"), camera: CameraName("backyard"), label: "motorcycle", severity: .alert,
            subLabel: nil, startTime: at(minutesAgo: 65), endTime: at(minutesAgo: 63),
            hasClip: true, hasSnapshot: false, isObjectDetection: true, verdict: .incorrect,
            score: 0.71, zones: []
        ),
        Event(
            id: EventId("evt-4"), camera: CameraName("front_door"), label: "person", severity: .alert,
            subLabel: "delivery", startTime: at(minutesAgo: 130), endTime: at(minutesAgo: 128),
            hasClip: false, hasSnapshot: true, isObjectDetection: true, verdict: nil,
            score: 0.9, zones: ["porch"]
        ),
        Event(
            id: EventId("evt-5"), camera: CameraName("garage"), label: "cat", severity: .detection,
            subLabel: nil, startTime: at(minutesAgo: 260), endTime: at(minutesAgo: 259),
            hasClip: true, hasSnapshot: true, isObjectDetection: true, verdict: nil,
            score: nil, zones: []
        ),
        Event(
            id: EventId("evt-6"), camera: CameraName("driveway"), label: "car", severity: .detection,
            subLabel: nil, startTime: at(minutesAgo: 1_500), endTime: at(minutesAgo: 1_495),
            hasClip: true, hasSnapshot: true, isObjectDetection: true, verdict: nil,
            score: 0.82, zones: ["driveway"]
        ),
    ]
}

/// The same six events, all `.detection` — exercises the "LATEST EVENT" hero fallback (decision
/// #4) when no alert is loaded.
private func snapshotDetections() -> [Event] {
    snapshotEvents().map { event in
        Event(
            id: event.id, camera: event.camera, label: event.label, severity: .detection,
            subLabel: event.subLabel, startTime: event.startTime, endTime: event.endTime,
            hasClip: event.hasClip, hasSnapshot: event.hasSnapshot,
            isObjectDetection: event.isObjectDetection, verdict: event.verdict,
            score: event.score, zones: event.zones
        )
    }
}

private func snapshotVerifiedEvent() -> [Event] {
    [
        Event(
            id: EventId("evt-verified"), camera: CameraName("driveway"), label: "motorcycle",
            severity: .alert, subLabel: nil,
            startTime: snapshotNow.addingTimeInterval(-22 * 60),
            endTime: snapshotNow.addingTimeInterval(-21 * 60),
            hasClip: true, hasSnapshot: true, isObjectDetection: true, verdict: .correct,
            score: 0.88, zones: ["driveway"]
        ),
    ]
}

// MARK: - View builder

/// The events list screen, driven to a terminal state before rendering so the view's own
/// `.task` re-load settles on the same pixels. Thumbnails resolve to `nil`, pinning every row
/// to the deterministic placeholder.
@MainActor
private func eventsListScreen(
    events: Result<[Event], EventsError>,
    cameras: Result<[Camera], CamerasError> = .success(snapshotCameras()),
    filter: EventFilter = .all
) async -> some View {
    let viewModel = EventsListViewModel(
        getEvents: GetEvents(repository: FakeEventsRepository(events)),
        getCameras: GetCameras(repository: FakeCamerasRepository(cameras)),
        thumbnailLoader: FakeEventThumbnailLoader(),
        snapshotLoader: FakeEventSnapshotLoader(),
        now: { snapshotNow },
        calendar: {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            return calendar
        }()
    )
    await viewModel.load()
    if filter != .all {
        viewModel.select(filter)
    }

    return EventsListView(
        viewModel: viewModel,
        onOpenSettings: {},
        // Unused: the detail factory is never invoked in a list snapshot (no navigation happens).
        makeDetailViewModel: {
            let repository = FakeEventsRepository(.success([]))
            return EventDetailViewModel(
                event: $0,
                clipLoader: FakeEventClipLoader(),
                getEvent: GetEvent(repository: repository),
                isDetectionFeedbackEnabled: IsDetectionFeedbackEnabled(repository: repository),
                submitDetectionVerdict: SubmitDetectionVerdict(repository: repository)
            )
        }
    )
}
