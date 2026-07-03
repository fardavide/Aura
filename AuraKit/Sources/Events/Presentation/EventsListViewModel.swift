import Foundation
import Observation

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

    private let getEvents: GetEvents
    private let thumbnailLoader: any EventThumbnailLoading
    private let limit: Int

    public init(getEvents: GetEvents, thumbnailLoader: any EventThumbnailLoading, limit: Int = 100) {
        self.getEvents = getEvents
        self.thumbnailLoader = thumbnailLoader
        self.limit = limit
    }

    /// Fetches and replaces the content. Only the very first load shows the full-screen spinner
    /// (the initial state): a re-appearance re-fetches behind the current content, and a failed
    /// refresh keeps the last good content instead of swapping it for a full-screen error.
    public func load() async {
        do {
            let events = try await getEvents.execute(limit: limit)
            state = events.isEmpty ? .empty : .loaded(events)
        } catch {
            if case .loaded = state { return }
            state = .failed(error)
        }
    }

    public func thumbnail(for event: Event) async -> Data? {
        await thumbnailLoader.thumbnail(for: event.id)
    }
}
