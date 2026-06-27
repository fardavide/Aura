/// Wire shape of the parts of `GET /api/config` the Cameras feature reads. Internal —
/// it never leaves the Data layer.
struct ConfigDto: Decodable {
    let cameras: [String: CameraConfigDto]
}

struct CameraConfigDto: Decodable {
    let enabled: Bool?
    let friendlyName: String?
    let live: LiveDto?

    enum CodingKeys: String, CodingKey {
        case enabled
        case friendlyName = "friendly_name"
        case live
    }
}

struct LiveDto: Decodable {
    /// Maps a UI-friendly stream label to the go2rtc stream name; the values are the
    /// stream sources a client can view.
    let streams: [String: String]?
}
