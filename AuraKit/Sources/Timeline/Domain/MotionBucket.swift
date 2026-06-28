import Foundation

/// Normalized motion intensity (0–100) for a time bucket — drives the timeline's activity strip.
public struct MotionBucket: Equatable, Sendable {
    public let time: Date
    public let intensity: Int

    public init(time: Date, intensity: Int) {
        self.time = time
        self.intensity = intensity
    }
}
