import Foundation

/// The glide after a scrub drag is released with speed: UIScrollView's deceleration curve applied
/// to the centre-anchored track, so a thrown timeline slides on and eases to a stop instead of
/// halting dead under the lifted finger.
///
/// Pure — the release velocity is fixed at creation and every offset is a function of elapsed
/// time, so the curve is unit-tested while the driving loop stays a thin piece of view code.
struct ScrubFling: Equatable {
    /// UIScrollView's `.normal` deceleration factor, restated per second (it is defined per
    /// millisecond), so the same feel carries over to a per-second time base.
    private static let decelerationPerSecond: CGFloat = pow(0.998, 1000)
    /// Releases slower than this are a positioning drag coming to rest, not a throw.
    private static let minimumVelocity: CGFloat = 80
    /// The residual speed that counts as stopped — the asymptote is never actually reached.
    private static let restVelocity: CGFloat = 8

    let initialVelocity: CGFloat

    /// `nil` when the release was too slow to read as a throw.
    init?(velocity: CGFloat) {
        guard abs(velocity) >= Self.minimumVelocity else { return nil }
        initialVelocity = velocity
    }

    /// Points travelled `elapsed` seconds after release, along the release direction.
    func offset(at elapsed: TimeInterval) -> CGFloat {
        let rate = Self.decelerationPerSecond
        return initialVelocity * (pow(rate, elapsed) - 1) / log(rate)
    }

    /// When the glide has slowed to the rest velocity — the moment to settle the scrub.
    var duration: TimeInterval {
        log(Self.restVelocity / abs(initialVelocity)) / log(Self.decelerationPerSecond)
    }
}
