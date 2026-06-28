/// Returns the saved theme, defaulting to `.system`.
public struct LoadTheme: Sendable {
    private let repository: any SettingsRepository

    public init(repository: any SettingsRepository) {
        self.repository = repository
    }

    public func execute() -> ThemePreference {
        repository.loadTheme()
    }
}
