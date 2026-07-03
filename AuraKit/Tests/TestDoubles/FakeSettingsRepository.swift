import SettingsDomain

/// In-memory settings store: loads return whatever was configured (or last saved), saves
/// overwrite it — so round-trip tests and pre-seeded screens use the same fake.
public final class FakeSettingsRepository: SettingsRepository, @unchecked Sendable {
    public var savedConnection: ConnectionSettings?
    public var savedTheme: ThemePreference

    public init(connection: ConnectionSettings? = nil, theme: ThemePreference = .system) {
        savedConnection = connection
        savedTheme = theme
    }

    public func loadConnection() -> ConnectionSettings? { savedConnection }
    public func saveConnection(_ settings: ConnectionSettings) { savedConnection = settings }
    public func loadTheme() -> ThemePreference { savedTheme }
    public func saveTheme(_ theme: ThemePreference) { savedTheme = theme }
}
