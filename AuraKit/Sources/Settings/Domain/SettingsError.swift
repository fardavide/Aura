/// Why a settings change was rejected.
public enum SettingsError: Error, Equatable, Sendable {
    case invalidHost
    case invalidPort
    /// The system refused to switch the Home Screen icon, or the platform has no icon to switch.
    case iconChangeFailed
}
