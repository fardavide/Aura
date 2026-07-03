import Foundation
import Testing

import CamerasDomain
import CommonFrigate
import CommonNetwork
import EventsDomain
import TestDoubles
@testable import EventsData

struct EventDecodingTests {

    @Test func `when decoding events then fields map to the domain`() throws {
        // given - when
        let events = try decodeEvents()
        let first = try #require(events.first)

        // then
        #expect(first.id == EventId("ev1"))
        #expect(first.camera == CameraName("driveway"))
        #expect(first.label == "person")
        #expect(first.startTime == Date(timeIntervalSince1970: 1_707_000_000))
        #expect(first.endTime == Date(timeIntervalSince1970: 1_707_000_060))
        #expect(first.hasClip == true)
        #expect(first.score == 0.87)
        #expect(first.zones == ["yard"])
    }

    @Test func `given an in-progress event then end time is nil and clip is false`() throws {
        // given - when
        let garage = try #require(decodeEvents().first { $0.id == EventId("ev2") })

        // then
        #expect(garage.endTime == nil)
        #expect(garage.hasClip == false)
        #expect(garage.score == nil)
        #expect(garage.zones == [])
    }
}

struct FrigateEventsRepositoryTests {

    @Test func `given a 200 response when fetching events then they are decoded`() async throws {
        // given
        let sut = FrigateEventsRepository(
            config: .test,
            httpClient: FakeHttpClient(.response(status: 200, body: Data(eventsJson.utf8)))
        )

        // when
        let events = try await sut.events(limit: 10)

        // then
        #expect(events.map(\.id) == [EventId("ev1"), EventId("ev2")])
    }

    @Test func `given a 401 when fetching events then it throws notAuthorized`() async {
        let sut = FrigateEventsRepository(
            config: .test, httpClient: FakeHttpClient(.response(status: 401, body: Data()))
        )
        await #expect(throws: EventsError.notAuthorized) { try await sut.events(limit: 10) }
    }

    @Test func `given malformed json when fetching events then it throws invalidData`() async {
        let sut = FrigateEventsRepository(
            config: .test, httpClient: FakeHttpClient(.response(status: 200, body: Data("nope".utf8)))
        )
        await #expect(throws: EventsError.invalidData) { try await sut.events(limit: 10) }
    }
}

struct FrigateEventClipLoaderTests {

    @Test func `given a 200 response when downloading a clip then it returns the bytes`() async {
        // given
        let bytes = Data([0x00, 0x01, 0x02])
        let sut = FrigateEventClipLoader(
            config: .test,
            httpClient: FakeHttpClient(.response(status: 200, body: bytes))
        )

        // when - then
        #expect(await sut.downloadClip(for: event(hasClip: true)) == bytes)
    }

    @Test func `given a non-success status when downloading a clip then it is nil`() async {
        let sut = FrigateEventClipLoader(
            config: .test,
            httpClient: FakeHttpClient(.response(status: 404, body: Data()))
        )
        #expect(await sut.downloadClip(for: event(hasClip: true)) == nil)
    }
}

// MARK: - Fixtures

private func decodeEvents() throws -> [Event] {
    try JSONDecoder().decode([EventDto].self, from: Data(eventsJson.utf8)).toEvents()
}

private func event(hasClip: Bool) -> Event {
    Event(
        id: EventId("ev1"), camera: CameraName("driveway"), label: "person", subLabel: nil,
        startTime: Date(timeIntervalSince1970: 0), endTime: nil,
        hasClip: hasClip, hasSnapshot: true, score: nil, zones: []
    )
}

private let eventsJson = """
[
  {
    "id": "ev1", "camera": "driveway", "label": "person", "sub_label": null,
    "start_time": 1707000000.0, "end_time": 1707000060.0,
    "has_clip": true, "has_snapshot": true, "zones": ["yard"],
    "data": { "score": 0.87, "top_score": 0.9 }
  },
  {
    "id": "ev2", "camera": "garage", "label": "car",
    "start_time": 1707000100.0, "end_time": null,
    "has_clip": false, "has_snapshot": true, "data": {}
  }
]
"""

extension ServerConfig {
    static let test = ServerConfig(
        scheme: .http, host: "frigate.test", port: 5000, username: nil, password: nil
    )
}
