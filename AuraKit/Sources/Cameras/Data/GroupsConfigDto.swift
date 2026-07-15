import Foundation

/// The `camera_groups` slice of `GET /api/config`. Internal — it never leaves the Data layer.
struct GroupsConfigDto: Decodable {
    let cameraGroups: [String: CameraGroupDto]?

    enum CodingKeys: String, CodingKey {
        case cameraGroups = "camera_groups"
    }
}

struct CameraGroupDto: Decodable {
    /// Frigate serialises a group's cameras as `Union[str, list[str]]` — either a JSON array or a
    /// comma-joined string (what its web UI writes). `CommaSeparableStrings` accepts both.
    let cameras: CommaSeparableStrings?
    let order: Int?
}

/// Decodes a value that Frigate may serialise as a JSON array *or* a comma-joined string.
struct CommaSeparableStrings: Decodable {
    let values: [String]

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let list = try? container.decode([String].self) {
            values = list
        } else {
            values = try container.decode(String.self)
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }
}
