import Foundation

/// Returns one page of events, newest first. `before` walks the page window backwards through
/// history — `nil` is the newest page.
public struct GetEvents: Sendable {
    private let repository: any EventsRepository

    public init(repository: any EventsRepository) {
        self.repository = repository
    }

    public func execute(limit: Int, before: Date?) async throws(EventsError) -> [Event] {
        try await repository.events(limit: limit, before: before).sorted { $0.startTime > $1.startTime }
    }
}
