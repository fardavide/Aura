/// Re-reads one event from the server, so a screen opened from a stale list sees the verdict that
/// is on record now rather than the one that was when the list loaded.
public struct GetEvent: Sendable {
    private let repository: any EventsRepository

    public init(repository: any EventsRepository) {
        self.repository = repository
    }

    public func execute(_ id: EventId) async throws(EventsError) -> Event {
        try await repository.event(id: id)
    }
}
