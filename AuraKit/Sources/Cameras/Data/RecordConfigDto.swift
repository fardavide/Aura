/// The `record` retention slice of `GET /api/config`. Internal — it never leaves the Data layer.
/// Frigate 0.17 has no single "retain days" field; retention is split across four knobs (continuous
/// / motion recordings, plus alert / detection clip retention), each a `days` float.
struct RecordConfigDto: Decodable {
    let record: RecordDto?
}

struct RecordDto: Decodable {
    let continuous: RetainDaysDto?
    let motion: RetainDaysDto?
    let alerts: ClipRetainDto?
    let detections: ClipRetainDto?
}

struct RetainDaysDto: Decodable {
    let days: Double?
}

struct ClipRetainDto: Decodable {
    let retain: RetainDaysDto?
}
