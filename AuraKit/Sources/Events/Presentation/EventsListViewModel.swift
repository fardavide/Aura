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

    /// Where the list stands on **older** events, independently of `state` — the loaded content is
    /// never blanked to page, so the two are orthogonal.
    public enum Paging: Equatable {
        /// Older events may exist and nothing is in flight.
        case ready
        case loading
        /// The last page failed; the footer offers a retry.
        case failed
        /// The server has no older events to give.
        case exhausted
    }

    public private(set) var state: State = .loading
    public private(set) var paging: Paging = .exhausted
    public private(set) var filter: EventFilter = .all

    private let getEvents: GetEvents
    private let getCameras: GetCameras
    private let thumbnailLoader: any EventThumbnailLoading
    private let snapshotLoader: any EventSnapshotLoading
    private let now: @MainActor () -> Date
    private let calendar: Calendar
    private let limit: Int
    private var cameraNames: [CameraName: String] = [:]
    /// Frigate's cursor is exclusive (`start_time < before`), so paging on the oldest event's exact
    /// start time would silently drop anything sharing that instant. Nudging a millisecond past it
    /// re-serves the boundary event instead — harmless, since the page is deduplicated by id.
    private let cursorNudge: TimeInterval = 0.001

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

    /// How much history is held. The footer keys its auto-paging on this, so a page that lands
    /// re-arms the trigger while it is still on screen.
    public var loadedCount: Int {
        allEvents.count
    }

    public func select(_ filter: EventFilter) {
        self.filter = filter
    }

    /// Fetches and replaces the content. Only the very first load shows the full-screen spinner
    /// (the initial state): a re-appearance re-fetches behind the current content, and a failed
    /// refresh keeps the last good content instead of swapping it for a full-screen error.
    public func load() async {
        do {
            let events = try await getEvents.execute(limit: limit, before: nil)
            state = events.isEmpty ? .empty : .loaded(events)
            paging = events.count < limit ? .exhausted : .ready
            if !events.labelFilters().contains(filter) {
                filter = .all
            }
        } catch {
            if case .loaded = state { return }
            state = .failed(error)
            paging = .exhausted
        }
        // Best-effort: a failed camera read leaves the map empty and rows fall back to the slug.
        cameraNames = ((try? await getCameras.execute()) ?? []).reduce(into: [:]) {
            $0[$1.name] = $1.friendlyName
        }
    }

    /// Appends the page of events immediately older than the oldest one held. Loaded content is
    /// never blanked or replaced — a failure only parks `paging` on `.failed` so the footer can
    /// offer a retry.
    public func loadMore() async {
        switch paging {
        case .ready, .failed: break
        case .loading, .exhausted: return
        }
        guard case .loaded(let current) = state, let oldest = current.map(\.startTime).min() else { return }
        paging = .loading
        do {
            let page = try await getEvents.execute(limit: limit, before: oldest.addingTimeInterval(cursorNudge))
            let known = Set(current.map(\.id))
            let added = page.filter { !known.contains($0.id) }
            state = .loaded((current + added).sorted { $0.startTime > $1.startTime })
            // A page that adds nothing is the other end condition: without it a window where every
            // event shares the cursor's start time would be re-requested forever.
            paging = added.isEmpty || page.count < limit ? .exhausted : .ready
        } catch {
            paging = .failed
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
