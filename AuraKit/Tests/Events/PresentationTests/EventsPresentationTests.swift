import Foundation
import Testing

import CamerasEntities
import EventsDomain
import TestDoubles
@testable import EventsPresentation

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
            thumbnailLoader: FakeEventThumbnailLoader()
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
            thumbnailLoader: FakeEventThumbnailLoader()
        )
        await sut.load()

        // when
        repository.result = .failure(.serverUnavailable)
        await sut.load()

        // then
        #expect(sut.state == .loaded([event("ev1")]))
    }
}

@MainActor
struct EventDetailViewModelTests {

    @Test func `given an event with no clip then it is unavailable`() {
        let sut = EventDetailViewModel(event: event("ev1", hasClip: false), clipLoader: FakeEventClipLoader(nil))
        #expect(sut.state == .unavailable)
    }

    @Test func `given a clip when loading then it becomes ready`() async {
        let sut = EventDetailViewModel(event: event("ev1"), clipLoader: FakeEventClipLoader(Data([0x01, 0x02])))
        await sut.load()
        #expect(sut.state == .ready(Data([0x01, 0x02])))
        #expect(sut.title == "person")
    }

    @Test func `given a failing download when loading then it fails`() async {
        let sut = EventDetailViewModel(event: event("ev1"), clipLoader: FakeEventClipLoader(nil))
        await sut.load()
        #expect(sut.state == .failed)
    }
}

// MARK: - Helpers

@MainActor
private func makeViewModel(_ result: Result<[Event], EventsError>) -> EventsListViewModel {
    EventsListViewModel(
        getEvents: GetEvents(repository: FakeEventsRepository(result)),
        thumbnailLoader: FakeEventThumbnailLoader()
    )
}

private func event(_ id: String, hasClip: Bool = true) -> Event {
    Event(
        id: EventId(id), camera: CameraName("driveway"), label: "person", subLabel: nil,
        startTime: Date(timeIntervalSince1970: 1), endTime: nil,
        hasClip: hasClip, hasSnapshot: true, score: nil, zones: []
    )
}
