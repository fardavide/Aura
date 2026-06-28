import Foundation

/// One element of `/api/review/activity/motion` — a normalized motion-intensity bucket.
struct MotionActivityDto: Decodable {
    let startTime: Double
    let motion: Double

    enum CodingKeys: String, CodingKey {
        case motion
        case startTime = "start_time"
    }
}
