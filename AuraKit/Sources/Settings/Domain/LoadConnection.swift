/// Returns the saved connection settings, if any.
public struct LoadConnection: Sendable {
    private let repository: any SettingsRepository

    public init(repository: any SettingsRepository) {
        self.repository = repository
    }

    public func execute() -> ConnectionSettings? {
        repository.loadConnection()
    }
}
