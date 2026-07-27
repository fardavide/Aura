/// One element of the camera recordings list. The response also carries an id, motion/object
/// counts and the file size; playback needs none of them.
struct RecordingSegmentDto: Decodable {
    let startTime: Double
    let endTime: Double
    let duration: Double

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case duration
    }
}
