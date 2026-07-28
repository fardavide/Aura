import CamerasEntities

/// Which cameras a timeline read covers: the whole deployment (the Timeline tab's synced grid) or
/// one camera (its detail screen). An enum rather than an optional `CameraName` so "every camera"
/// is a named state the compiler can enumerate, not an absent one every caller must interpret.
public enum TimelineScope: Equatable, Sendable {
    case allCameras
    case camera(CameraName)

    /// The cameras to ask the server for. Empty means "don't narrow the query" — which is how the
    /// server means all of them.
    public var cameraNames: [CameraName] {
        switch self {
        case .allCameras: []
        case .camera(let name): [name]
        }
    }
}
