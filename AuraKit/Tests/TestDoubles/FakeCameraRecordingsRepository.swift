import Foundation

import CamerasEntities
import TimelineDomain

/// Serves fixed recording segments for every camera and window. Reassign `result` mid-test to
/// change what a later window fetch returns — new footage, a gap, or a failure.
public final class FakeCameraRecordingsRepository: CameraRecordingsRepository, @unchecked Sendable {
    public var result: Result<[RecordingSegment], TimelineError>
    public var source: CameraStreamSource
    /// The window of the most recent fetch — asserted on when a test pins which hour was loaded.
    public private(set) var lastWindow: TimeRange?
    public private(set) var fetchCount = 0
    /// Awaited mid-fetch with the 1-based call index when set — lets a test hold one window load
    /// open and interleave another, so out-of-order landings are exercised deterministically.
    public var onSegments: (@Sendable (Int) async -> Void)?

    public init(
        _ result: Result<[RecordingSegment], TimelineError>,
        source: CameraStreamSource = CameraStreamSource(url: URL(filePath: "/unused"), headers: [:])
    ) {
        self.result = result
        self.source = source
    }

    public func segments(for camera: CameraName, in window: TimeRange) async throws(TimelineError) -> [RecordingSegment] {
        fetchCount += 1
        lastWindow = window
        if let onSegments { await onSegments(fetchCount) }
        return try result.get()
    }

    public func playbackSource(for camera: CameraName, in window: TimeRange) -> CameraStreamSource {
        source
    }
}
