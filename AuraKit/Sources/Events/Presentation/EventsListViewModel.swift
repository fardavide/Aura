import Foundation
import Observation

import CamerasDomain
import CamerasEntities
import EventsDomain

@Observable
@MainActor
public final class EventsListViewModel {
    public enum State: Equatable {
        case loading
        case loaded([Event])
        case empty
        case failed(EventsError)
    }

    public private(set) var state: State = .loading
    public private(set) var filter: EventFilter = .all

    private let getEvents: GetEvents
    private let getCameras: GetCameras
    private let thumbnailLoader: any EventThumbnailLoading
    private let snapshotLoader: any EventSnapshotLoading
    private let now: @MainActor () -> Date
    private let calendar: Calendar
    private let limit: Int
    private var cameraNames: [CameraName: String] = [:]

    public init(
        getEvents: GetEvents,
        getCameras: GetCameras,
        thumbnailLoader: any EventThumbnailLoading,
        snapshotLoader: any EventSnapshotLoading,
        now: @escaping @MainActor () -> Date,
        calendar: Calendar,
        limit: Int = 100
    ) {
        self.getEvents = getEvents
        self.getCameras = getCameras
        self.thumbnailLoader = thumbnailLoader
        self.snapshotLoader = snapshotLoader
        self.now = now
        self.calendar = calendar
        self.limit = limit
    }

    /// Every loaded event, newest first, regardless of `filter` — `nil` outside `.loaded`/`.empty`.
    private var allEvents: [Event] {
        switch state {
        case .loaded(let events): events
        case .empty: []
        case .loading, .failed: []
        }
    }

    /// `nil` in `.loading` and `.failed` — those states know nothing about the day; `.empty` and
    /// `.loaded` return the real value (possibly a zero total).
    public var summary: EventsSummary? {
        switch state {
        case .loading, .failed: nil
        case .loaded, .empty: allEvents.matching(filter).summary(onDayOf: now(), calendar: calendar)
        }
    }

    /// The chip row — built from **every** loaded event, so a chip never vanishes because its own
    /// filter is currently active.
    public var filters: [EventFilter] {
        allEvents.labelFilters()
    }

    public var hero: Event? {
        allEvents.matching(filter).mostSignificant()
    }

    public var groups: [EventHourGroup] {
        allEvents.matching(filter).groupedByHour(calendar: calendar)
    }

    public func select(_ filter: EventFilter) {
        self.filter = filter
    }

    /// Fetches and replaces the content. Only the very first load shows the full-screen spinner
    /// (the initial state): a re-appearance re-fetches behind the current content, and a failed
    /// refresh keeps the last good content instead of swapping it for a full-screen error.
    public func load() async {
        do {
            let events = try await getEvents.execute(limit: limit)
            state = events.isEmpty ? .empty : .loaded(events)
            if !events.labelFilters().contains(filter) {
                filter = .all
            }
        } catch {
            if case .loaded = state { return }
            state = .failed(error)
        }
        // Best-effort: a failed camera read leaves the map empty and rows fall back to the slug.
        cameraNames = ((try? await getCameras.execute()) ?? []).reduce(into: [:]) {
            $0[$1.name] = $1.friendlyName
        }
    }

    public func displayName(for camera: CameraName) -> String {
        cameraNames[camera] ?? camera.value
    }

    /// The subtitle string, `nil` when `summary` is `nil`. `"Today · No events"` when the day's
    /// total is 0 (never a dangling separator); otherwise `"Today · N events"` plus one
    /// `"· C label"` clause per breakdown entry, truncated to `maximumLabels` (`nil` = all).
    public func summaryText(maximumLabels: Int?) -> String? {
        guard let summary else { return nil }
        guard summary.total > 0 else { return "Today · No events" }
        let eventsClause = "Today · \(summary.total) event\(summary.total == 1 ? "" : "s")"
        let breakdown = maximumLabels.map { Array(summary.breakdown.prefix($0)) } ?? summary.breakdown
        let labelClauses = breakdown.map { "\($0.count) \($0.label)" }
        return ([eventsClause] + labelClauses).joined(separator: " · ")
    }

    /// `nil` when the event is still in progress (`endTime == nil`).
    public func durationText(for event: Event) -> String? {
        guard let endTime = event.endTime else { return nil }
        return Duration.seconds(endTime.timeIntervalSince(event.startTime))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2))
    }

    public func countText(for group: EventHourGroup) -> String {
        "\(group.events.count) event\(group.events.count == 1 ? "" : "s")"
    }

    public enum EventDayContext: Equatable, Sendable {
        case today
        case otherDay
    }

    public func dayContext(of instant: Date) -> EventDayContext {
        calendar.isDate(instant, inSameDayAs: now()) ? .today : .otherDay
    }

    public func thumbnail(for event: Event) async -> Data? {
        await thumbnailLoader.thumbnail(for: event.id)
    }

    public func heroImage(for event: Event) async -> Data? {
        if event.hasSnapshot, let snapshot = await snapshotLoader.snapshot(for: event.id) {
            return snapshot
        }
        return await thumbnailLoader.thumbnail(for: event.id)
    }
}
