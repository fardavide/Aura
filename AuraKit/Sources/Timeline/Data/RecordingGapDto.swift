import Foundation

/// One element of `/api/recordings/unavailable` — a span with no recorded footage.
struct RecordingGapDto: Decodable {
    let startTime: Double
    let endTime: Double

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
    }
}
