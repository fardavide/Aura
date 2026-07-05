import CamerasEntities

/// Returns the saved camera display order.
public struct LoadCameraOrder: Sendable {
    private let repository: any SettingsRepository

    public init(repository: any SettingsRepository) {
        self.repository = repository
    }

    public func execute() -> [CameraName] {
        repository.loadCameraOrder()
    }
}
