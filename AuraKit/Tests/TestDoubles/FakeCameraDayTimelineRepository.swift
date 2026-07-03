import Foundation

import TimelineDomain

/// Replays a canned result; `result` is mutable so a test can change the outcome between a load
/// and a refresh. Records every queried range so span extension is assertable.
public final class FakeCameraDayTimelineRepository: CameraDayTimelineRepository, @unchecked Sendable {
    public var result: Result<DayTimeline, TimelineError>
    public private(set) var queriedRanges: [TimeRange] = []

    public init(_ result: Result<DayTimeline, TimelineError>) {
        self.result = result
    }

    public func dayTimeline(in range: TimeRange) async throws(TimelineError) -> DayTimeline {
        queriedRanges.append(range)
        return try result.get()
    }
}
