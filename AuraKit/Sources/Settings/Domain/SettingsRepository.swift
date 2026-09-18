import CamerasEntities

/// Persistence boundary for settings. Implemented in the Data layer (UserDefaults +
/// Keychain); the Domain knows nothing of how or where values are stored.
public protocol SettingsRepository: Sendable {
    func loadConnection() -> ConnectionSettings?
    func saveConnection(_ settings: ConnectionSettings)
    func loadTheme() -> ThemePreference
    func saveTheme(_ theme: ThemePreference)
    func loadCameraOrder() -> [CameraName]
    func saveCameraOrder(_ order: [CameraName])
    func observeCameraOrder() -> AsyncStream<[CameraName]>
    func loadDynamicCameraOrder() -> Bool
    func saveDynamicCameraOrder(_ isEnabled: Bool)
    func observeDynamicCameraOrder() -> AsyncStream<Bool>
}
