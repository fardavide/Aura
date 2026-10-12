import Foundation

import CamerasEntities

/// A bounded section of an original recording file, with its wall-clock coverage.
public struct RecordingClip: Equatable, Sendable {
    public let source: CameraStreamSource
    public let range: TimeRange
    public let sourceOffset: TimeInterval
    public let duration: TimeInterval

    public init(source: CameraStreamSource, range: TimeRange, sourceOffset: TimeInterval, duration: TimeInterval) {
        self.source = source
        self.range = range
        self.sourceOffset = sourceOffset
        self.duration = duration
    }
}
