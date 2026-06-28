/// Why saving connection settings was rejected.
public enum SettingsError: Error, Equatable, Sendable {
    case invalidHost
    case invalidPort
}
