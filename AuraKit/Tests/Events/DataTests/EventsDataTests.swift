import Foundation
import Testing

import CamerasEntities
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

struct EventReviewDecodingTests {

    @Test func `when decoding review items then severity and detection ids map to the wire`() throws {
        // given - when
        let reviews = try JSONDecoder().decode([EventReviewDto].self, from: Data(alertReviewJson.utf8))

        // then
        #expect(reviews[0].severity == "alert")
        #expect(reviews[0].data?.detections == ["ev1"])
        #expect(reviews[1].severity == "detection")
        #expect(reviews[1].data?.detections == ["ev2"])
    }

    @Test func `given an item with no data when decoding then its detections are nil`() throws {
        // given - when
        let reviews = try JSONDecoder().decode([EventReviewDto].self, from: Data(alertReviewJson.utf8))

        // then
        #expect(reviews[2].data == nil)
    }

    @Test func `given alert and detection items when collecting alert event ids then only the alert ids are returned`() throws {
        // given
        let reviews = try JSONDecoder().decode([EventReviewDto].self, from: Data(alertReviewJson.utf8))

        // when - then
        #expect(reviews.alertEventIds() == ["ev1"])
    }

    @Test func `given an unknown severity when collecting alert event ids then it contributes nothing`() throws {
        // given
        let reviews = try JSONDecoder().decode(
            [EventReviewDto].self,
            from: Data(significantMotionReviewJson.utf8)
        )

        // when - then
        #expect(reviews.alertEventIds().isEmpty)
    }
}

struct FrigateEventsRepositoryTests {

    @Test func `given a 200 response when fetching events then they are decoded`() async throws {
        // given
        let sut = FrigateEventsRepository(
            config: .test,
            httpClient: FakeHttpClient(routes: [
                ("api/events", .response(status: 200, body: Data(eventsJson.utf8))),
                ("api/review", .response(status: 200, body: Data(emptyReviewJson.utf8))),
            ])
        )

        // when
        let events = try await sut.events(limit: 10)

        // then
        #expect(events.map(\.id) == [EventId("ev1"), EventId("ev2")])
    }

    @Test func `when fetching events then the request carries a bounded timeout`() async throws {
        // given
        let http = FakeHttpClient(routes: [
            ("api/events", .response(status: 200, body: Data(eventsJson.utf8))),
            ("api/review", .response(status: 200, body: Data(emptyReviewJson.utf8))),
        ])
        let sut = FrigateEventsRepository(config: .test, httpClient: http)

        // when
        _ = try await sut.events(limit: 10)

        // then
        #expect(http.lastRequest?.timeoutInterval == 15)
    }

    @Test func `given a 401 when fetching events then it throws notAuthorized`() async {
        let sut = FrigateEventsRepository(
            config: .test,
            httpClient: FakeHttpClient(routes: [("api/events", .response(status: 401, body: Data()))])
        )
        await #expect(throws: EventsError.notAuthorized) { try await sut.events(limit: 10) }
    }

    @Test func `given malformed json when fetching events then it throws invalidData`() async {
        let sut = FrigateEventsRepository(
            config: .test,
            httpClient: FakeHttpClient(routes: [("api/events", .response(status: 200, body: Data("nope".utf8)))])
        )
        await #expect(throws: EventsError.invalidData) { try await sut.events(limit: 10) }
    }

    @Test func `given an event listed by an alert review item when fetching events then it is an alert`() async throws {
        // given
        let sut = FrigateEventsRepository(
            config: .test,
            httpClient: FakeHttpClient(routes: [
                ("api/events", .response(status: 200, body: Data(eventsJson.utf8))),
                ("api/review", .response(status: 200, body: Data(alertReviewJson.utf8))),
            ])
        )

        // when
        let events = try await sut.events(limit: 10)

        // then
        #expect(events.first { $0.id == EventId("ev1") }?.severity == .alert)
    }

    @Test func `given an event listed only by a detection review item when fetching events then it is a detection`() async throws {
        // given
        let sut = FrigateEventsRepository(
            config: .test,
            httpClient: FakeHttpClient(routes: [
                ("api/events", .response(status: 200, body: Data(eventsJson.utf8))),
                ("api/review", .response(status: 200, body: Data(alertReviewJson.utf8))),
            ])
        )

        // when
        let events = try await sut.events(limit: 10)

        // then
        #expect(events.first { $0.id == EventId("ev2") }?.severity == .detection)
    }

    @Test func `given a failing review read when fetching events then every event is a detection`() async throws {
        // given
        let sut = FrigateEventsRepository(
            config: .test,
            httpClient: FakeHttpClient(routes: [
                ("api/events", .response(status: 200, body: Data(eventsJson.utf8))),
                ("api/review", .response(status: 500, body: Data())),
            ])
        )

        // when
        let events = try await sut.events(limit: 10)

        // then
        #expect(events.allSatisfy { $0.severity == .detection })
    }

    @Test func `given malformed review json when fetching events then every event is a detection`() async throws {
        // given
        let sut = FrigateEventsRepository(
            config: .test,
            httpClient: FakeHttpClient(routes: [
                ("api/events", .response(status: 200, body: Data(eventsJson.utf8))),
                ("api/review", .response(status: 200, body: Data("nope".utf8))),
            ])
        )

        // when
        let events = try await sut.events(limit: 10)

        // then
        #expect(events.allSatisfy { $0.severity == .detection })
    }

    @Test func `when fetching events then the review window spans the loaded events`() async throws {
        // given
        let http = FakeHttpClient(routes: [
            ("api/events", .response(status: 200, body: Data(eventsJson.utf8))),
            ("api/review", .response(status: 200, body: Data(emptyReviewJson.utf8))),
        ])
        let sut = FrigateEventsRepository(config: .test, httpClient: http)

        // when
        _ = try await sut.events(limit: 10)

        // then
        let reviewUrl = try #require(http.requestedUrls.first { $0.contains("api/review") })
        #expect(reviewUrl.contains("after=1707000000"))
        #expect(reviewUrl.contains("before=1707000100"))
    }

    @Test func `given no events when fetching events then the review endpoint is not called`() async throws {
        // given
        let http = FakeHttpClient(routes: [
            ("api/events", .response(status: 200, body: Data("[]".utf8))),
        ])
        let sut = FrigateEventsRepository(config: .test, httpClient: http)

        // when
        _ = try await sut.events(limit: 10)

        // then
        #expect(http.requestedUrls.count == 1)
    }
}

struct FrigateEventThumbnailLoaderTests {

    @Test func `when loading a thumbnail then the request carries a bounded timeout`() async {
        // given
        let http = FakeHttpClient(.response(status: 200, body: Data()))
        let sut = FrigateEventThumbnailLoader(config: .test, httpClient: http)

        // when
        _ = await sut.thumbnail(for: EventId("ev1"))

        // then
        #expect(http.lastRequest?.timeoutInterval == 15)
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

    @Test func `when downloading a clip then the request carries a bounded timeout`() async {
        // given
        let http = FakeHttpClient(.response(status: 200, body: Data()))
        let sut = FrigateEventClipLoader(config: .test, httpClient: http)

        // when
        _ = await sut.downloadClip(for: event(hasClip: true))

        // then
        #expect(http.lastRequest?.timeoutInterval == 15)
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
        id: EventId("ev1"), camera: CameraName("driveway"), label: "person", severity: .detection,
        subLabel: nil, startTime: Date(timeIntervalSince1970: 0), endTime: nil,
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

private let emptyReviewJson = "[]"

/// One alert item listing `ev1`, one detection item listing `ev2`, and one alert item with no
/// `data` at all (tolerant decoding: its `detections` reads as `nil`, contributing nothing).
private let alertReviewJson = """
[
  { "severity": "alert", "data": { "detections": ["ev1"] } },
  { "severity": "detection", "data": { "detections": ["ev2"] } },
  { "severity": "alert" }
]
"""

private let significantMotionReviewJson = """
[
  { "severity": "significant_motion", "data": { "detections": ["ev1"] } }
]
"""

extension ServerConfig {
    static let test = ServerConfig(
        scheme: .http, host: "frigate.test", port: 5000, username: nil, password: nil
    )
}
