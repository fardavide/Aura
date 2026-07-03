import EventsDomain

/// Replays a canned result; `result` is mutable so a test can change the outcome between calls.
public final class FakeEventsRepository: EventsRepository, @unchecked Sendable {
    public var result: Result<[Event], EventsError>

    public init(_ result: Result<[Event], EventsError>) {
        self.result = result
    }

    public func events(limit: Int) async throws(EventsError) -> [Event] {
        try result.get()
    }
}
