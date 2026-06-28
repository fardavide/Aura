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

    public func load() async {
        state = .loading
        do {
            let events = try await getEvents.execute(limit: limit)
            state = events.isEmpty ? .empty : .loaded(events)
        } catch {
            state = .failed(error)
        }
    }

    public func thumbnail(for event: Event) async -> Data? {
        await thumbnailLoader.thumbnail(for: event.id)
    }
}
