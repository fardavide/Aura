/// Wire shape of one `/api/exports` element (snake_case from Frigate).
///
/// `date` is a number despite the column being a `DateTimeField`: the row is written with
/// `Export.date: self.start_time`, the export's epoch-seconds start (verified against v0.17.2
/// `frigate/record/export.py`). `thumb_path` is non-null in the schema, but is decoded optionally
/// so a server that ever omits it degrades to the placeholder instead of failing the whole list.
struct ExportDto: Decodable {
    let id: String
    let camera: String
    let name: String
    let date: Double
    let videoPath: String
    let thumbPath: String?
    let inProgress: Bool?

    enum CodingKeys: String, CodingKey {
        case id, camera, name, date
        case videoPath = "video_path"
        case thumbPath = "thumb_path"
        case inProgress = "in_progress"
    }
}
