/// Wire shape of one `/api/events` element (snake_case from Frigate).
struct EventDto: Decodable {
    let id: String
    let camera: String
    let label: String
    let subLabel: String?
    let startTime: Double
    let endTime: Double?
    let hasClip: Bool?
    let hasSnapshot: Bool?
    let zones: [String]?
    let data: EventDataDto?

    enum CodingKeys: String, CodingKey {
        case id, camera, label, zones, data
        case subLabel = "sub_label"
        case startTime = "start_time"
        case endTime = "end_time"
        case hasClip = "has_clip"
        case hasSnapshot = "has_snapshot"
    }
}

struct EventDataDto: Decodable {
    let score: Double?
    let topScore: Double?

    enum CodingKeys: String, CodingKey {
        case score
        case topScore = "top_score"
    }
}
