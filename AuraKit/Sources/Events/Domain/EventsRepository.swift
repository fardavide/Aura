/// The boundary the Events feature depends on to read events. Implemented in the Data layer.
public protocol EventsRepository: Sendable {
    func events(limit: Int) async throws(EventsError) -> [Event]
}
