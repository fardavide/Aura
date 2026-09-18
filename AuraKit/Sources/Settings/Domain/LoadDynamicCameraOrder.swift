/// Returns whether the walls may promote the camera with the newest alert ahead of the user's
/// saved order, defaulting to enabled.
public struct LoadDynamicCameraOrder: Sendable {
    private let repository: any SettingsRepository

    public init(repository: any SettingsRepository) {
        self.repository = repository
    }

    public func execute() -> Bool {
        repository.loadDynamicCameraOrder()
    }
}
