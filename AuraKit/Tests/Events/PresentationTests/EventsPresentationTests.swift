import Foundation
import Testing

import CamerasDomain
import CamerasEntities
import EventsDomain
import TestDoubles
@testable import EventsPresentation

/// The instant every test's `now()` resolves to, and the calendar used throughout — GMT
/// gregorian, explicit, never `Calendar.current`, so a hour/day boundary never depends on the
/// machine's time zone.
private let snapshotInstant = Date(timeIntervalSince1970: 1_000_000)
private let gmtCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}()

@MainActor
struct EventsListViewModelTests {

    @Test func `given events when loading then the state is loaded`() async {
        let sut = makeViewModel(.success([event("ev1")]))
        await sut.load()
        #expect(sut.state == .loaded([event("ev1")]))
    }

    @Test func `given no events when loading then the state is empty`() async {
        let sut = makeViewModel(.success([]))
        await sut.load()
        #expect(sut.state == .empty)
    }

    @Test func `given a failure when loading then the state carries the error`() async {
        let sut = makeViewModel(.failure(.serverUnavailable))
        await sut.load()
        #expect(sut.state == .failed(.serverUnavailable))
    }

    @Test func `given a loaded state when loading again then the fresh content is shown`() async {
        // given
        let repository = FakeEventsRepository(.success([event("ev1")]))
        let sut = EventsListViewModel(
            getEvents: GetEvents(repository: repository),
            getCameras: GetCameras(repository: FakeCamerasRepository(.success([]))),
            thumbnailLoader: FakeEventThumbnailLoader(),
            snapshotLoader: FakeEventSnapshotLoader(),
            now: { snapshotInstant },
            calendar: gmtCalendar
        )
        await sut.load()

        // when
        repository.result = .success([event("ev2")])
        await sut.load()

        // then
        #expect(sut.state == .loaded([event("ev2")]))
    }

    @Test func `given a loaded state when a refresh fails then the last good content is kept`() async {
        // given
        let repository = FakeEventsRepository(.success([event("ev1")]))
        let sut = EventsListViewModel(
            getEvents: GetEvents(repository: repository),
            getCameras: GetCameras(repository: FakeCamerasRepository(.success([]))),
            thumbnailLoader: FakeEventThumbnailLoader(),
            snapshotLoader: FakeEventSnapshotLoader(),
            now: { snapshotInstant },
            calendar: gmtCalendar
        )
        await sut.load()

        // when
        repository.result = .failure(.serverUnavailable)
        await sut.load()

        // then
        #expect(sut.state == .loaded([event("ev1")]))
    }

    @Test func `given loaded events when reading the groups then they are grouped by hour newest first`() async {
        // given
        let older = event("older", severity: .detection, label: "person", startTime: snapshotInstant.addingTimeInterval(-3_700))
        let newer = event("newer", severity: .detection, label: "person", startTime: snapshotInstant)
        let sut = makeViewModel(.success([older, newer]))

        // when
        await sut.load()

        // then
        #expect(sut.groups.map(\.events) == [[newer], [older]])
    }

    @Test func `given an alert among the loaded events when reading the hero then it is the newest alert`() async {
        // given
        let alert = event("alert", severity: .alert, label: "person", startTime: snapshotInstant.addingTimeInterval(-100))
        let newerDetection = event("detection", severity: .detection, label: "car", startTime: snapshotInstant)
        let sut = makeViewModel(.success([alert, newerDetection]))

        // when
        await sut.load()

        // then
        #expect(sut.hero == alert)
    }

    @Test func `given only detections when reading the hero then it is the newest event`() async {
        // given
        let older = event("older", severity: .detection, label: "person", startTime: snapshotInstant.addingTimeInterval(-100))
        let newer = event("newer", severity: .detection, label: "person", startTime: snapshotInstant)
        let sut = makeViewModel(.success([older, newer]))

        // when
        await sut.load()

        // then
        #expect(sut.hero == newer)
    }

    @Test func `given loaded events when reading the filters then all comes first`() async {
        // given
        let sut = makeViewModel(.success([
            event("a", label: "person"),
            event("b", label: "car"),
        ]))

        // when
        await sut.load()

        // then
        #expect(sut.filters.first == .all)
    }

    @Test func `given a label selected when reading the groups then only that label is shown`() async {
        // given
        let person = event("a", label: "person", startTime: snapshotInstant)
        let car = event("b", label: "car", startTime: snapshotInstant.addingTimeInterval(-10))
        let sut = makeViewModel(.success([person, car]))
        await sut.load()

        // when
        sut.select(.label("person"))

        // then
        #expect(sut.groups.flatMap(\.events) == [person])
    }

    @Test func `given a label selected when reading the summary then it counts only that label`() async {
        // given
        let person = event("a", label: "person", startTime: snapshotInstant)
        let car = event("b", label: "car", startTime: snapshotInstant.addingTimeInterval(-10))
        let sut = makeViewModel(.success([person, car]))
        await sut.load()

        // when
        sut.select(.label("person"))

        // then
        #expect(sut.summary?.total == 1)
    }

    @Test func `given a label selected when reading the filters then every label is still offered`() async {
        // given
        let person = event("a", label: "person", startTime: snapshotInstant)
        let car = event("b", label: "car", startTime: snapshotInstant.addingTimeInterval(-10))
        let sut = makeViewModel(.success([person, car]))
        await sut.load()

        // when
        sut.select(.label("person"))

        // then
        #expect(Set(sut.filters) == Set([.all, .label("person"), .label("car")]))
    }

    @Test func `given a label selected when reading the hero then it is that label's newest alert`() async {
        // given
        let personAlert = event("a", severity: .alert, label: "person", startTime: snapshotInstant.addingTimeInterval(-10))
        let carAlert = event("b", severity: .alert, label: "car", startTime: snapshotInstant)
        let sut = makeViewModel(.success([personAlert, carAlert]))
        await sut.load()

        // when
        sut.select(.label("person"))

        // then
        #expect(sut.hero == personAlert)
    }

    @Test func `given a selected label absent from a reload when loading then the filter falls back to all`() async {
        // given
        let repository = FakeEventsRepository(.success([event("a", label: "person")]))
        let sut = EventsListViewModel(
            getEvents: GetEvents(repository: repository),
            getCameras: GetCameras(repository: FakeCamerasRepository(.success([]))),
            thumbnailLoader: FakeEventThumbnailLoader(),
            snapshotLoader: FakeEventSnapshotLoader(),
            now: { snapshotInstant },
            calendar: gmtCalendar
        )
        await sut.load()
        sut.select(.label("person"))

        // when
        repository.result = .success([event("b", label: "car")])
        await sut.load()

        // then
        #expect(sut.filter == .all)
    }

    @Test func `given events from another day when reading the summary then only today is counted`() async {
        // given
        let today = event("a", startTime: snapshotInstant)
        let yesterday = event("b", startTime: snapshotInstant.addingTimeInterval(-86_400))
        let sut = makeViewModel(.success([today, yesterday]))

        // when
        await sut.load()

        // then
        #expect(sut.summary?.total == 1)
    }

    @Test func `given cameras with friendly names when reading a display name then the friendly name is used`() async {
        // given
        let sut = makeViewModel(
            .success([event("a")]),
            cameras: .success([Camera(name: CameraName("driveway"), friendlyName: "Driveway", isEnabled: true, streamNames: [])])
        )

        // when
        await sut.load()

        // then
        #expect(sut.displayName(for: CameraName("driveway")) == "Driveway")
    }

    @Test func `given an unknown camera when reading a display name then the slug is used`() async {
        // given
        let sut = makeViewModel(.success([event("a")]), cameras: .success([]))

        // when
        await sut.load()

        // then
        #expect(sut.displayName(for: CameraName("driveway")) == "driveway")
    }

    @Test func `given a failing camera read when reading a display name then the slug is used`() async {
        // given
        let sut = makeViewModel(.success([event("a")]), cameras: .failure(.unreachable))

        // when
        await sut.load()

        // then
        #expect(sut.displayName(for: CameraName("driveway")) == "driveway")
        #expect(sut.state == .loaded([event("a")]))
    }

    @Test func `given an event with a snapshot when loading the hero image then the snapshot bytes are used`() async {
        // given
        let sut = EventsListViewModel(
            getEvents: GetEvents(repository: FakeEventsRepository(.success([event("a")]))),
            getCameras: GetCameras(repository: FakeCamerasRepository(.success([]))),
            thumbnailLoader: FakeEventThumbnailLoader(thumbnail: Data([0x02])),
            snapshotLoader: FakeEventSnapshotLoader(snapshot: Data([0x01])),
            now: { snapshotInstant },
            calendar: gmtCalendar
        )

        // when - then
        #expect(await sut.heroImage(for: event("a")) == Data([0x01]))
    }

    @Test func `given an event without a snapshot when loading the hero image then the thumbnail bytes are used`() async {
        // given
        let sut = EventsListViewModel(
            getEvents: GetEvents(repository: FakeEventsRepository(.success([]))),
            getCameras: GetCameras(repository: FakeCamerasRepository(.success([]))),
            thumbnailLoader: FakeEventThumbnailLoader(thumbnail: Data([0x02])),
            snapshotLoader: FakeEventSnapshotLoader(snapshot: Data([0x01])),
            now: { snapshotInstant },
            calendar: gmtCalendar
        )
        let eventWithoutSnapshot = event("a", hasSnapshot: false)

        // when - then
        #expect(await sut.heroImage(for: eventWithoutSnapshot) == Data([0x02]))
    }

    @Test func `given a snapshot that fails to load when loading the hero image then the thumbnail bytes are used`() async {
        // given
        let sut = EventsListViewModel(
            getEvents: GetEvents(repository: FakeEventsRepository(.success([]))),
            getCameras: GetCameras(repository: FakeCamerasRepository(.success([]))),
            thumbnailLoader: FakeEventThumbnailLoader(thumbnail: Data([0x02])),
            snapshotLoader: FakeEventSnapshotLoader(snapshot: nil),
            now: { snapshotInstant },
            calendar: gmtCalendar
        )

        // when - then
        #expect(await sut.heroImage(for: event("a")) == Data([0x02]))
    }
}

@MainActor
struct EventsListViewModelPagingTests {

    @Test func `given a full first page when loading then older events may still exist`() async {
        // given
        let scenario = Scenario(first: .success([event("a", startTime: at(300)), event("b", startTime: at(200))]))

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.paging == .ready)
    }

    @Test func `given a short first page when loading then there are no older events`() async {
        // given
        let scenario = Scenario(first: .success([event("a", startTime: at(300))]))

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.paging == .exhausted)
    }

    @Test func `given a full first page when loading more then the older events are appended oldest last`() async {
        // given
        let scenario = Scenario(
            first: .success([event("a", startTime: at(300)), event("b", startTime: at(200))]),
            older: .success([event("c", startTime: at(100))])
        )
        await scenario.sut.load()

        // when
        await scenario.sut.loadMore()

        // then
        #expect(scenario.sut.state == .loaded([
            event("a", startTime: at(300)),
            event("b", startTime: at(200)),
            event("c", startTime: at(100)),
        ]))
    }

    @Test func `when loading more then the cursor sits just past the oldest loaded event`() async throws {
        // given
        let scenario = Scenario(
            first: .success([event("a", startTime: at(300)), event("b", startTime: at(200))]),
            older: .success([])
        )
        await scenario.sut.load()

        // when
        await scenario.sut.loadMore()

        // then
        let cursor = try #require(scenario.repository.requestedCursors.last ?? nil)
        #expect(cursor > at(200))
        #expect(cursor.timeIntervalSince(at(200)) < 1)
    }

    @Test func `given an older page repeating a loaded event when loading more then it is not duplicated`() async {
        // given
        let scenario = Scenario(
            first: .success([event("a", startTime: at(300)), event("b", startTime: at(200))]),
            older: .success([event("b", startTime: at(200)), event("c", startTime: at(100))])
        )
        await scenario.sut.load()

        // when
        await scenario.sut.loadMore()

        // then
        #expect(scenario.sut.state == .loaded([
            event("a", startTime: at(300)),
            event("b", startTime: at(200)),
            event("c", startTime: at(100)),
        ]))
    }

    @Test func `given a short older page when loading more then there is nothing left to load`() async {
        // given
        let scenario = Scenario(
            first: .success([event("a", startTime: at(300)), event("b", startTime: at(200))]),
            older: .success([event("c", startTime: at(100))])
        )
        await scenario.sut.load()

        // when
        await scenario.sut.loadMore()

        // then
        #expect(scenario.sut.paging == .exhausted)
    }

    @Test func `given a full older page adding nothing new when loading more then there is nothing left to load`() async {
        // given
        let scenario = Scenario(
            first: .success([event("a", startTime: at(300)), event("b", startTime: at(200))]),
            older: .success([event("a", startTime: at(300)), event("b", startTime: at(200))])
        )
        await scenario.sut.load()

        // when
        await scenario.sut.loadMore()

        // then
        #expect(scenario.sut.paging == .exhausted)
    }

    @Test func `given nothing left to load when loading more then the server is not asked again`() async {
        // given
        let scenario = Scenario(first: .success([event("a", startTime: at(300))]))
        await scenario.sut.load()

        // when
        await scenario.sut.loadMore()

        // then
        #expect(scenario.repository.requestedCursors == [nil])
    }

    @Test func `given a failing older page when loading more then the loaded events are kept`() async {
        // given
        let scenario = Scenario(
            first: .success([event("a", startTime: at(300)), event("b", startTime: at(200))]),
            older: .failure(.unreachable)
        )
        await scenario.sut.load()

        // when
        await scenario.sut.loadMore()

        // then
        #expect(scenario.sut.paging == .failed)
        #expect(scenario.sut.state == .loaded([
            event("a", startTime: at(300)),
            event("b", startTime: at(200)),
        ]))
    }

    @Test func `given a failed older page when loading more again then it is retried`() async {
        // given
        let scenario = Scenario(
            first: .success([event("a", startTime: at(300)), event("b", startTime: at(200))]),
            older: .failure(.unreachable)
        )
        await scenario.sut.load()
        await scenario.sut.loadMore()

        // when
        scenario.repository.olderResult = .success([event("c", startTime: at(100))])
        await scenario.sut.loadMore()

        // then
        #expect(scenario.sut.state == .loaded([
            event("a", startTime: at(300)),
            event("b", startTime: at(200)),
            event("c", startTime: at(100)),
        ]))
    }

    @Test func `given older events loaded when refreshing then paging is armed again`() async {
        // given
        let scenario = Scenario(
            first: .success([event("a", startTime: at(300)), event("b", startTime: at(200))]),
            older: .success([event("c", startTime: at(100))])
        )
        await scenario.sut.load()
        await scenario.sut.loadMore()

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.paging == .ready)
        #expect(scenario.sut.state == .loaded([
            event("a", startTime: at(300)),
            event("b", startTime: at(200)),
        ]))
    }

    @Test func `given a failed first load when loading more then the server is not asked`() async {
        // given
        let scenario = Scenario(first: .failure(.unreachable))
        await scenario.sut.load()

        // when
        await scenario.sut.loadMore()

        // then
        #expect(scenario.repository.requestedCursors == [nil])
    }

    @MainActor
    private struct Scenario {
        let repository: FakeEventsRepository
        let sut: EventsListViewModel

        init(
            first: Result<[Event], EventsError>,
            older: Result<[Event], EventsError>? = nil,
            limit: Int = 2
        ) {
            repository = FakeEventsRepository(first, olderResult: older)
            sut = EventsListViewModel(
                getEvents: GetEvents(repository: repository),
                getCameras: GetCameras(repository: FakeCamerasRepository(.success([]))),
                thumbnailLoader: FakeEventThumbnailLoader(),
                snapshotLoader: FakeEventSnapshotLoader(),
                now: { snapshotInstant },
                calendar: gmtCalendar,
                limit: limit
            )
        }
    }
}

@MainActor
struct EventDetailViewModelTests {

    @Test func `given an event with no clip then it is unavailable`() {
        let scenario = Scenario(event: event("ev1", hasClip: false))
        #expect(scenario.sut.state == .unavailable)
    }

    @Test func `given a clip when loading then it becomes ready`() async {
        let scenario = Scenario(event: event("ev1"), clip: Data([0x01, 0x02]))
        await scenario.sut.load()
        #expect(scenario.sut.state == .ready(Data([0x01, 0x02])))
        #expect(scenario.sut.label == "person")
    }

    @Test func `given a failing download when loading then it fails`() async {
        let scenario = Scenario(event: event("ev1"))
        await scenario.sut.load()
        #expect(scenario.sut.state == .failed)
    }

    @Test func `given a finished event when reading the header then it carries the label severity and duration`() {
        // given
        let finished = event(
            "ev1", severity: .alert, startTime: Date(timeIntervalSince1970: 0),
            endTime: Date(timeIntervalSince1970: 42)
        )

        // when
        let scenario = Scenario(event: finished)

        // then
        #expect(scenario.sut.label == "person")
        #expect(scenario.sut.severity == .alert)
        #expect(scenario.sut.startTime == Date(timeIntervalSince1970: 0))
        #expect(scenario.sut.duration == .seconds(42))
    }

    @Test func `given an in-progress event when reading the header then the duration is nil`() {
        // given
        let inProgress = event("ev1", endTime: nil)

        // when
        let scenario = Scenario(event: inProgress)

        // then
        #expect(scenario.sut.duration == nil)
    }

    @MainActor
    fileprivate struct Scenario {
        let repository: FakeEventsRepository
        let sut: EventDetailViewModel

        init(
            event: Event,
            clip: Data? = nil,
            feedbackEnabled: Result<Bool, EventsError> = .success(false),
            submit: Result<Void, EventsError> = .success(())
        ) {
            repository = FakeEventsRepository(
                .success([]), detectionFeedbackEnabled: feedbackEnabled, submitResult: submit
            )
            sut = EventDetailViewModel(
                event: event,
                clipLoader: FakeEventClipLoader(clip),
                isDetectionFeedbackEnabled: IsDetectionFeedbackEnabled(repository: repository),
                submitDetectionVerdict: SubmitDetectionVerdict(repository: repository)
            )
        }
    }
}

@MainActor
struct EventDetectionFeedbackTests {

    @Test func `given a server without detection feedback when loading it then nothing is offered`() async {
        // given
        let scenario = Scenario(event: finishedEvent(), feedbackEnabled: .success(false))

        // when
        await scenario.sut.loadFeedback()

        // then
        #expect(scenario.sut.feedback == .unavailable)
    }

    @Test func `given a server with detection feedback when loading it then a verdict can be given`() async {
        // given
        let scenario = Scenario(event: finishedEvent(), feedbackEnabled: .success(true))

        // when
        await scenario.sut.loadFeedback()

        // then
        #expect(scenario.sut.feedback == .ready)
    }

    @Test func `given an in-progress event when loading feedback then nothing is offered`() async {
        // given
        let scenario = Scenario(event: event("ev1", endTime: nil), feedbackEnabled: .success(true))

        // when
        await scenario.sut.loadFeedback()

        // then
        #expect(scenario.sut.feedback == .unavailable)
    }

    @Test func `given an event with no snapshot when loading feedback then nothing is offered`() async {
        // given
        let scenario = Scenario(event: finishedEvent(hasSnapshot: false), feedbackEnabled: .success(true))

        // when
        await scenario.sut.loadFeedback()

        // then
        #expect(scenario.sut.feedback == .unavailable)
    }

    @Test func `given an event that is not a tracked object when loading feedback then nothing is offered`() async {
        // given
        let scenario = Scenario(event: finishedEvent(isObjectDetection: false), feedbackEnabled: .success(true))

        // when
        await scenario.sut.loadFeedback()

        // then
        #expect(scenario.sut.feedback == .unavailable)
    }

    @Test func `given a failing availability read when loading feedback then nothing is offered`() async {
        // given
        let scenario = Scenario(event: finishedEvent(), feedbackEnabled: .failure(.unreachable))

        // when
        await scenario.sut.loadFeedback()

        // then
        #expect(scenario.sut.feedback == .unavailable)
    }

    @Test func `given an already submitted event when loading feedback then it reports the earlier submission`() async {
        // given
        let scenario = Scenario(event: finishedEvent(isSubmittedForTraining: true), feedbackEnabled: .success(true))

        // when
        await scenario.sut.loadFeedback()

        // then
        #expect(scenario.sut.feedback == .submitted(nil))
    }

    @Test func `given an offered verdict when confirming the label then it reaches the server`() async {
        // given
        let scenario = Scenario(event: finishedEvent(), feedbackEnabled: .success(true))
        await scenario.sut.loadFeedback()

        // when
        await scenario.sut.submit(.correct)

        // then
        #expect(scenario.repository.submittedVerdicts.map(\.verdict) == [.correct])
        #expect(scenario.repository.submittedVerdicts.map(\.event) == [EventId("ev1")])
        #expect(scenario.sut.feedback == .submitted(.correct))
    }

    @Test func `given an offered verdict when reporting the label wrong then it reaches the server`() async {
        // given
        let scenario = Scenario(event: finishedEvent(), feedbackEnabled: .success(true))
        await scenario.sut.loadFeedback()

        // when
        await scenario.sut.submit(.incorrect)

        // then
        #expect(scenario.repository.submittedVerdicts.map(\.verdict) == [.incorrect])
        #expect(scenario.sut.feedback == .submitted(.incorrect))
    }

    @Test func `given a failing submission when giving a verdict then the verdict is kept for the retry`() async {
        // given
        let scenario = Scenario(
            event: finishedEvent(), feedbackEnabled: .success(true), submit: .failure(.unreachable)
        )
        await scenario.sut.loadFeedback()

        // when
        await scenario.sut.submit(.incorrect)

        // then
        #expect(scenario.sut.feedback == .failed(.incorrect, .unreachable))
    }

    @Test func `given a failed submission when retrying then it is sent again`() async {
        // given
        let scenario = Scenario(
            event: finishedEvent(), feedbackEnabled: .success(true), submit: .failure(.unreachable)
        )
        await scenario.sut.loadFeedback()
        await scenario.sut.submit(.incorrect)

        // when
        scenario.repository.submitResult = .success(())
        await scenario.sut.submit(.incorrect)

        // then
        #expect(scenario.sut.feedback == .submitted(.incorrect))
        #expect(scenario.repository.submittedVerdicts.count == 2)
    }

    @Test func `given a verdict already given when loading feedback again then it is not walked back`() async {
        // given
        let scenario = Scenario(event: finishedEvent(), feedbackEnabled: .success(true))
        await scenario.sut.loadFeedback()
        await scenario.sut.submit(.correct)

        // when
        await scenario.sut.loadFeedback()

        // then
        #expect(scenario.sut.feedback == .submitted(.correct))
    }

    @Test func `given nothing is offered when submitting a verdict then the server is not called`() async {
        // given
        let scenario = Scenario(event: finishedEvent(), feedbackEnabled: .success(false))
        await scenario.sut.loadFeedback()

        // when
        await scenario.sut.submit(.correct)

        // then
        #expect(scenario.repository.submittedVerdicts.isEmpty)
        #expect(scenario.sut.feedback == .unavailable)
    }

    private typealias Scenario = EventDetailViewModelTests.Scenario

    private func finishedEvent(
        hasSnapshot: Bool = true,
        isObjectDetection: Bool = true,
        isSubmittedForTraining: Bool = false
    ) -> Event {
        event(
            "ev1",
            startTime: Date(timeIntervalSince1970: 0),
            endTime: Date(timeIntervalSince1970: 42),
            hasSnapshot: hasSnapshot,
            isObjectDetection: isObjectDetection,
            isSubmittedForTraining: isSubmittedForTraining
        )
    }
}

// MARK: - Helpers

@MainActor
private func makeViewModel(
    _ result: Result<[Event], EventsError>,
    cameras: Result<[Camera], CamerasError> = .success([]),
    snapshot: Data? = nil
) -> EventsListViewModel {
    EventsListViewModel(
        getEvents: GetEvents(repository: FakeEventsRepository(result)),
        getCameras: GetCameras(repository: FakeCamerasRepository(cameras)),
        thumbnailLoader: FakeEventThumbnailLoader(),
        snapshotLoader: FakeEventSnapshotLoader(snapshot: snapshot),
        now: { snapshotInstant },
        calendar: gmtCalendar
    )
}

private func at(_ epoch: TimeInterval) -> Date {
    Date(timeIntervalSince1970: epoch)
}

private func event(
    _ id: String,
    severity: EventSeverity = .detection,
    label: String = "person",
    startTime: Date = Date(timeIntervalSince1970: 1),
    endTime: Date? = nil,
    hasClip: Bool = true,
    hasSnapshot: Bool = true,
    isObjectDetection: Bool = true,
    isSubmittedForTraining: Bool = false
) -> Event {
    Event(
        id: EventId(id), camera: CameraName("driveway"), label: label, severity: severity,
        subLabel: nil, startTime: startTime, endTime: endTime,
        hasClip: hasClip, hasSnapshot: hasSnapshot, isObjectDetection: isObjectDetection,
        isSubmittedForTraining: isSubmittedForTraining, score: nil, zones: []
    )
}
