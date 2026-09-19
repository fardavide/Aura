import Foundation

import EventsDomain

/// Replays a canned result; `result` is mutable so a test can change the outcome between calls.
/// `olderResult`, when set, answers only the cursored reads (the older pages), leaving `result`
/// as the newest page — so one fake covers a first load followed by a paged load.
public final class FakeEventsRepository: EventsRepository, @unchecked Sendable {
    public var result: Result<[Event], EventsError>
    public var olderResult: Result<[Event], EventsError>?
    public private(set) var requestedCursors: [Date?] = []

    public init(_ result: Result<[Event], EventsError>, olderResult: Result<[Event], EventsError>? = nil) {
        self.result = result
        self.olderResult = olderResult
    }

    public func events(limit: Int, before: Date?) async throws(EventsError) -> [Event] {
        requestedCursors.append(before)
        if before != nil, let olderResult {
            return try olderResult.get()
        }
        return try result.get()
    }
}
