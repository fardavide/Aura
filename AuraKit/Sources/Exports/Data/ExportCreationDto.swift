/// The body Frigate's start-export handler takes (`ExportRecordingsBody`). Only the two knobs this
/// app exercises are sent: real-time speed, cut from the recordings rather than the previews.
///
/// `name`, `image_path` and `chapters` are deliberately absent rather than null — omitting the name
/// is what makes Frigate supply its own timestamp-derived one, which this app never overrides.
struct ExportRequestDto: Encodable {
    let playback: String
    let source: String
}

/// What the handler answers with. Only the id matters — the row it names already exists with
/// `in_progress` true, and everything else about the clip is read back through `/api/exports/{id}`.
struct ExportCreationDto: Decodable {
    let exportId: String

    enum CodingKeys: String, CodingKey {
        case exportId = "export_id"
    }
}
