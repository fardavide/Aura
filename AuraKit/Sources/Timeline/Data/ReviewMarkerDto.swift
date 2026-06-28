import Foundation

/// One element of `/api/review` — an activity segment shown as a timeline marker.
struct ReviewMarkerDto: Decodable {
    let startTime: Double
    let endTime: Double?
    let severity: String

    enum CodingKeys: String, CodingKey {
        case severity
        case startTime = "start_time"
        case endTime = "end_time"
    }
}
