import Foundation

/// One element of `/api/review` — an activity segment shown as a timeline marker.
struct ReviewMarkerDto: Decodable {
    let camera: String
    let startTime: Double
    let endTime: Double?
    let severity: String
    let data: ReviewMarkerDataDto?

    struct ReviewMarkerDataDto: Decodable {
        let objects: [String]?
    }

    enum CodingKeys: String, CodingKey {
        case camera, severity, data
        case startTime = "start_time"
        case endTime = "end_time"
    }
}
