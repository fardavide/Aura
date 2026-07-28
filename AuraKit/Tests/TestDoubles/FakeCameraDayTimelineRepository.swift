import Foundation

import TimelineDomain

/// Replays a canned result; `result` is mutable so a test can change the outcome between one
/// window and the next. Records every queried range, scope, and bucket so the window walk, camera
/// scoping, and the span-derived resolution are all assertable.
public final class FakeCameraDayTimelineRepository: CameraDayTimelineRepository, @unchecked Sendable {
    public var result: Result<DayTimeline, TimelineError>
    /// Awaited mid-fetch when set — lets a test interleave work while a query is in flight.
    public var onQuery: (@Sendable () async -> Void)?
    public private(set) var queriedRanges: [TimeRange] = []
    public private(set) var queriedScopes: [TimelineScope] = []
    public private(set) var queriedBuckets: [TimeInterval] = []

    public init(_ result: Result<DayTimeline, TimelineError>) {
        self.result = result
    }

    public func dayTimeline(
        for scope: TimelineScope,
        in range: TimeRange,
        bucket: TimeInterval
    ) async throws(TimelineError) -> DayTimeline {
        queriedRanges.append(range)
        queriedScopes.append(scope)
        queriedBuckets.append(bucket)
        if let onQuery { await onQuery() }
        return try result.get()
    }
}
