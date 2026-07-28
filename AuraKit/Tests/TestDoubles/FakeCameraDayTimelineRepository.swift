import Foundation

import TimelineDomain

/// Replays a canned result; `result` is mutable so a test can change the outcome between a load
/// and a refresh. Records every queried range and scope so span extension and camera scoping are
/// assertable.
public final class FakeCameraDayTimelineRepository: CameraDayTimelineRepository, @unchecked Sendable {
    public var result: Result<DayTimeline, TimelineError>
    /// Awaited mid-fetch when set — lets a test interleave work while a query is in flight.
    public var onQuery: (@Sendable () async -> Void)?
    public private(set) var queriedRanges: [TimeRange] = []
    public private(set) var queriedScopes: [TimelineScope] = []

    public init(_ result: Result<DayTimeline, TimelineError>) {
        self.result = result
    }

    public func dayTimeline(for scope: TimelineScope, in range: TimeRange) async throws(TimelineError) -> DayTimeline {
        queriedRanges.append(range)
        queriedScopes.append(scope)
        if let onQuery { await onQuery() }
        return try result.get()
    }
}
