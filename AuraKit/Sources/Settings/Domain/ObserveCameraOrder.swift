import CamerasEntities

/// Streams the camera display order: the current value immediately, then every change.
public struct ObserveCameraOrder: Sendable {
    private let repository: any SettingsRepository

    public init(repository: any SettingsRepository) {
        self.repository = repository
    }

    public func execute() -> AsyncStream<[CameraName]> {
        repository.observeCameraOrder()
    }
}
