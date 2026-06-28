/// Persists the user's theme choice.
public struct SaveTheme: Sendable {
    private let repository: any SettingsRepository

    public init(repository: any SettingsRepository) {
        self.repository = repository
    }

    public func execute(_ theme: ThemePreference) {
        repository.saveTheme(theme)
    }
}
