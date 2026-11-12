import Foundation

/// The short glide after a deliberate flick of the centre-anchored track.
///
/// Pure — the release velocity is fixed at creation and every offset is a function of elapsed
/// time, so the curve is unit-tested while the driving loop stays a thin piece of view code.
struct ScrubFling: Equatable {
    let initialVelocity: CGFloat

    private static let decelerationPerSecond: CGFloat = pow(0.994, 1000)
    /// Also subtracted from the glide speed, so a release just above the threshold barely coasts.
    private static let settleVelocity: CGFloat = 180

    /// `nil` when the release was too slow to read as a throw.
    init?(velocity: CGFloat) {
        guard abs(velocity) > Self.settleVelocity else { return nil }
        initialVelocity = velocity
    }

    /// Points travelled `elapsed` seconds after release, along the release direction.
    func offset(at elapsed: TimeInterval) -> CGFloat {
        let rate = Self.decelerationPerSecond
        let time = min(elapsed, duration)
        let projectedTravel = abs(initialVelocity) * (pow(rate, time) - 1) / log(rate)
        // Subtract the residual speed throughout the glide so it eases all the way to rest.
        let travel = projectedTravel - Self.settleVelocity * time
        return initialVelocity < 0 ? -travel : travel
    }

    /// The time when the damped glide reaches zero speed.
    var duration: TimeInterval {
        log(Self.settleVelocity / abs(initialVelocity)) / log(Self.decelerationPerSecond)
    }
}
