/// Wire shape of one `/api/review` item — the Events-local slice (decision #4). `ReviewItemDto` /
/// `ReviewMarkerDto` in the Timeline/Cameras verticals decode the same endpoint for their own
/// needs; this type never leaves the Data layer.
struct EventReviewDto: Decodable {
    let severity: String
    let data: EventReviewDataDto?
}

struct EventReviewDataDto: Decodable {
    /// Ids of the `/api/events` items this review period covers.
    let detections: [String]?
}
