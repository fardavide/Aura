/// Returns recent events, newest first.
public struct GetEvents: Sendable {
    private let repository: any EventsRepository

    public init(repository: any EventsRepository) {
        self.repository = repository
    }

    public func execute(limit: Int) async throws(EventsError) -> [Event] {
        try await repository.events(limit: limit).sorted { $0.startTime > $1.startTime }
    }
}
