import Foundation

import CamerasDomain

/// Replays canned event labels; records the `since` bound it was queried with so a test can assert
/// the day window. `result` is mutable so a test can change the outcome between calls.
public final class FakeTodayEventsRepository: TodayEventsRepository, @unchecked Sendable {
    public var result: Result<[String], CamerasError>
    public private(set) var lastSince: Date?

    public init(_ result: Result<[String], CamerasError>) {
        self.result = result
    }

    public func labels(since: Date) async throws(CamerasError) -> [String] {
        lastSince = since
        return try result.get()
    }
}
