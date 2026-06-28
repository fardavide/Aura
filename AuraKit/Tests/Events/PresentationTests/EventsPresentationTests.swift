import Foundation
import Testing

import CamerasDomain
import EventsDomain
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
}

@MainActor
struct EventDetailViewModelTests {

    @Test func `given an event with no clip then it is unavailable`() {
        let sut = EventDetailViewModel(event: event("ev1", hasClip: false), clipLoader: StubClipLoader(nil))
        #expect(sut.state == .unavailable)
    }

    @Test func `given a clip when loading then it becomes ready`() async {
        let sut = EventDetailViewModel(event: event("ev1"), clipLoader: StubClipLoader(Data([0x01, 0x02])))
        await sut.load()
        #expect(sut.state == .ready(Data([0x01, 0x02])))
        #expect(sut.title == "person")
    }

    @Test func `given a failing download when loading then it fails`() async {
        let sut = EventDetailViewModel(event: event("ev1"), clipLoader: StubClipLoader(nil))
        await sut.load()
        #expect(sut.state == .failed)
    }
}

// MARK: - Helpers

@MainActor
private func makeViewModel(_ result: Result<[Event], EventsError>) -> EventsListViewModel {
    EventsListViewModel(
        getEvents: GetEvents(repository: StubEventsRepository(result)),
        thumbnailLoader: StubThumbnailLoader()
    )
}

private func event(_ id: String, hasClip: Bool = true) -> Event {
    Event(
        id: EventId(id), camera: CameraName("driveway"), label: "person", subLabel: nil,
        startTime: Date(timeIntervalSince1970: 1), endTime: nil,
        hasClip: hasClip, hasSnapshot: true, score: nil, zones: []
    )
}

private final class StubEventsRepository: EventsRepository, @unchecked Sendable {
    private let result: Result<[Event], EventsError>
    init(_ result: Result<[Event], EventsError>) { self.result = result }
    func events(limit: Int) async throws(EventsError) -> [Event] { try result.get() }
}

private final class StubThumbnailLoader: EventThumbnailLoading, @unchecked Sendable {
    func thumbnail(for event: EventId) async -> Data? { nil }
}

private final class StubClipLoader: EventClipLoading, @unchecked Sendable {
    private let data: Data?
    init(_ data: Data?) { self.data = data }
    func downloadClip(for event: Event) async -> Data? { data }
}
