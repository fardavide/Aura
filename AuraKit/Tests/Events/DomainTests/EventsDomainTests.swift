import Foundation
import Testing

import CamerasEntities
import TestDoubles
@testable import EventsDomain

struct GetEventsTests {

    @Test func `when getting events then they are newest first`() async throws {
        // given
        let sut = GetEvents(repository: FakeEventsRepository(.success([
            event("older", at: 100),
            event("newer", at: 200),
        ])))

        // when
        let result = try await sut.execute(limit: 10)

        // then
        #expect(result.map(\.id) == [EventId("newer"), EventId("older")])
    }
}

private func event(
    _ id: String,
    at epoch: TimeInterval,
    label: String = "person",
    severity: EventSeverity = .detection
) -> Event {
    Event(
        id: EventId(id),
        camera: CameraName("driveway"),
        label: label,
        severity: severity,
        subLabel: nil,
        startTime: Date(timeIntervalSince1970: epoch),
        endTime: nil,
        hasClip: true,
        hasSnapshot: true,
        score: nil,
        zones: []
    )
}

/// GMT gregorian, explicit and never `Calendar.current` — every hour/day boundary in these tests
/// must be independent of the machine's time zone.
private let gmtCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}()

struct EventCollectionsTests {

    @Test func `given the all filter when matching then every event is kept`() {
        let events = [event("a", at: 0), event("b", at: 100)]
        #expect(events.matching(.all) == events)
    }

    @Test func `given a label filter when matching then only that label is kept`() {
        let events = [
            event("a", at: 0, label: "person"),
            event("b", at: 100, label: "car"),
        ]
        #expect(events.matching(.label("car")) == [event("b", at: 100, label: "car")])
    }

    @Test func `given no events when building label filters then there are none`() {
        let events: [Event] = []
        #expect(events.labelFilters() == [])
    }

    @Test func `given mixed labels when building label filters then all comes first then labels by descending count`() {
        let events = [
            event("a", at: 0, label: "person"),
            event("b", at: 1, label: "car"),
            event("c", at: 2, label: "person"),
        ]
        #expect(events.labelFilters() == [.all, .label("person"), .label("car")])
    }

    @Test func `given labels with equal counts when building label filters then they are ordered alphabetically`() {
        let events = [
            event("a", at: 0, label: "dog"),
            event("b", at: 1, label: "cat"),
        ]
        #expect(events.labelFilters() == [.all, .label("cat"), .label("dog")])
    }

    @Test func `given events in two hours when grouping by hour then each group holds only its hour`() {
        let first = event("a", at: 0)
        let second = event("b", at: 3600)
        let groups = [first, second].groupedByHour(calendar: gmtCalendar)
        #expect(groups.map(\.events) == [[second], [first]])
    }

    @Test func `given events in two hours when grouping by hour then the newest hour comes first`() {
        let older = event("a", at: 0)
        let newer = event("b", at: 3600)
        let groups = [older, newer].groupedByHour(calendar: gmtCalendar)
        #expect(groups.map(\.hourStart) == [
            gmtCalendar.dateInterval(of: .hour, for: newer.startTime)!.start,
            gmtCalendar.dateInterval(of: .hour, for: older.startTime)!.start,
        ])
    }

    @Test func `given events in one hour when grouping by hour then the newest event comes first`() {
        let older = event("a", at: 0)
        let newer = event("b", at: 60)
        let groups = [older, newer].groupedByHour(calendar: gmtCalendar)
        #expect(groups.map(\.events) == [[newer, older]])
    }

    @Test func `given no events when grouping by hour then there are no groups`() {
        let events: [Event] = []
        #expect(events.groupedByHour(calendar: gmtCalendar) == [])
    }

    @Test func `given an alert older than the newest detection when picking the most significant then the alert wins`() {
        let alert = event("a", at: 0, severity: .alert)
        let detection = event("b", at: 100, severity: .detection)
        #expect([alert, detection].mostSignificant() == alert)
    }

    @Test func `given only detections when picking the most significant then the newest event wins`() {
        let older = event("a", at: 0, severity: .detection)
        let newer = event("b", at: 100, severity: .detection)
        #expect([older, newer].mostSignificant() == newer)
    }

    @Test func `given no events when picking the most significant then it is nil`() {
        let events: [Event] = []
        #expect(events.mostSignificant() == nil)
    }

    @Test func `given events from yesterday and today when summarizing then only today is counted`() {
        let today = event("a", at: 100_000)
        let yesterday = event("b", at: 100_000 - 86_400)
        let summary = [today, yesterday].summary(onDayOf: Date(timeIntervalSince1970: 100_000), calendar: gmtCalendar)
        #expect(summary.total == 1)
    }

    @Test func `given today's events when summarizing then the breakdown is most frequent first`() {
        let events = [
            event("a", at: 100_000, label: "person"),
            event("b", at: 100_001, label: "car"),
            event("c", at: 100_002, label: "person"),
        ]
        let summary = events.summary(onDayOf: Date(timeIntervalSince1970: 100_000), calendar: gmtCalendar)
        #expect(summary.breakdown == [
            EventsSummary.LabelCount(label: "person", count: 2),
            EventsSummary.LabelCount(label: "car", count: 1),
        ])
    }

    @Test func `given no events today when summarizing then the total is zero and the breakdown is empty`() {
        let yesterday = event("a", at: 100_000 - 86_400)
        let summary = [yesterday].summary(onDayOf: Date(timeIntervalSince1970: 100_000), calendar: gmtCalendar)
        #expect(summary.total == 0)
        #expect(summary.breakdown == [])
    }
}
