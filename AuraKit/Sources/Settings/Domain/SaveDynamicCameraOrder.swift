/// Stores whether the walls may promote the camera with the newest alert ahead of the user's
/// saved order.
public struct SaveDynamicCameraOrder: Sendable {
    private let repository: any SettingsRepository

    public init(repository: any SettingsRepository) {
        self.repository = repository
    }

    public func execute(_ isEnabled: Bool) {
        repository.saveDynamicCameraOrder(isEnabled)
    }
}
