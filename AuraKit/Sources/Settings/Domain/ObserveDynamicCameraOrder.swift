/// Streams whether the walls may promote the camera with the newest alert: the current value
/// immediately, then every change — so a wall on screen settles back to the saved order the
/// moment the preference is turned off.
public struct ObserveDynamicCameraOrder: Sendable {
    private let repository: any SettingsRepository

    public init(repository: any SettingsRepository) {
        self.repository = repository
    }

    public func execute() -> AsyncStream<Bool> {
        repository.observeDynamicCameraOrder()
    }
}
