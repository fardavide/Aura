import CamerasEntities

/// The activity to surface on the grid — at most one per camera, the most recently started.
public struct GetCameraActivity: Sendable {
    private let repository: any CameraActivityRepository

    public init(repository: any CameraActivityRepository) {
        self.repository = repository
    }

    public func execute() async throws(CamerasError) -> [CameraName: CameraActivity] {
        var latest: [CameraName: CameraActivity] = [:]
        for activity in try await repository.activeActivity() {
            if let existing = latest[activity.camera], existing.startedAt >= activity.startedAt {
                continue
            }
            latest[activity.camera] = activity
        }
        return latest
    }
}
