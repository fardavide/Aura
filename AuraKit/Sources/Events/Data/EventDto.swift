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
    /// Non-nil once the event's snapshot has been uploaded to Frigate+.
    let plusId: String?
    /// Set by the false-positive submission — the server's record that the label was reported wrong.
    let falsePositive: Bool?
    let zones: [String]?
    let data: EventDataDto?

    enum CodingKeys: String, CodingKey {
        case id, camera, label, zones, data
        case subLabel = "sub_label"
        case startTime = "start_time"
        case endTime = "end_time"
        case hasClip = "has_clip"
        case hasSnapshot = "has_snapshot"
        case plusId = "plus_id"
        case falsePositive = "false_positive"
    }
}

struct EventDataDto: Decodable {
    let score: Double?
    let topScore: Double?
    /// `object`, `audio` or `manual`. Absent on events old enough to predate the field.
    let type: String?

    enum CodingKeys: String, CodingKey {
        case score, type
        case topScore = "top_score"
    }
}

/// The slice of `/api/config` that says whether this deployment can take detection feedback.
struct PlusConfigDto: Decodable {
    let plus: PlusFlagDto?
}

struct PlusFlagDto: Decodable {
    let enabled: Bool?
}
