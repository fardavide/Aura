/// The parts of a `/api/review` item the Cameras feature reads to badge live tiles. Internal —
/// it never leaves the Data layer.
struct ReviewItemDto: Decodable {
    let camera: String
    let startTime: Double
    let endTime: Double?
    let severity: String
    let data: ReviewItemDataDto?

    enum CodingKeys: String, CodingKey {
        case camera
        case severity
        case data
        case startTime = "start_time"
        case endTime = "end_time"
    }
}

struct ReviewItemDataDto: Decodable {
    /// The tracked objects, e.g. `["person"]` — the first is shown on the tile badge.
    let objects: [String]?
}
