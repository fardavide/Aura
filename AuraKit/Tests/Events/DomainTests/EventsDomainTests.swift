import Foundation
import Testing

import CamerasDomain
@testable import EventsDomain

struct GetEventsTests {

    @Test func `when getting events then they are newest first`() async throws {
        // given
        let sut = GetEvents(repository: StubEventsRepository([
            event("older", at: 100),
            event("newer", at: 200),
        ]))

        // when
        let result = try await sut.execute(limit: 10)

        // then
        #expect(result.map(\.id) == [EventId("newer"), EventId("older")])
    }
}

private func event(_ id: String, at epoch: TimeInterval) -> Event {
    Event(
        id: EventId(id),
        camera: CameraName("driveway"),
        label: "person",
        subLabel: nil,
        startTime: Date(timeIntervalSince1970: epoch),
        endTime: nil,
        hasClip: true,
        hasSnapshot: true,
        score: nil,
        zones: []
    )
}

private final class StubEventsRepository: EventsRepository, @unchecked Sendable {
    private let stubbed: [Event]
    init(_ stubbed: [Event]) { self.stubbed = stubbed }
    func events(limit: Int) async throws(EventsError) -> [Event] { stubbed }
}
