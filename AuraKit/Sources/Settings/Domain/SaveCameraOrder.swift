import CamerasEntities

/// Persists the user's camera display order.
public struct SaveCameraOrder: Sendable {
    private let repository: any SettingsRepository

    public init(repository: any SettingsRepository) {
        self.repository = repository
    }

    public func execute(_ order: [CameraName]) {
        repository.saveCameraOrder(order)
    }
}
