/// Why a settings change was rejected. The connection cases name the address that failed —
/// two addresses are editable on one screen, so "invalid port" alone would leave the user
/// hunting for which field it meant.
public enum SettingsError: Error, Equatable, Sendable {
    case invalidHost(ServerRoute)
    case invalidPort(ServerRoute)
    /// The system refused to switch the Home Screen icon, or the platform has no icon to switch.
    case iconChangeFailed
}
